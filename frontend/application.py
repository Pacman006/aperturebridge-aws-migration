"""ApertureBridge: migration reference web portal for Elastic Beanstalk."""
import logging
import os
import uuid
from pathlib import Path
from urllib.parse import urlparse
from flask import Flask, Response, jsonify, render_template, request
from sqlalchemy import select, insert, text
from werkzeug.utils import secure_filename
from shared.models import assets
from shared.settings import aws_client, flag, get_engine

MAX_BYTES = 10 * 1024 * 1024
# S3 POST policy measures the complete multipart body, not just image bytes.
MAX_FORM_BYTES = MAX_BYTES + 8192
MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}
application = Flask(__name__)
application.config["MAX_CONTENT_LENGTH"] = MAX_BYTES + 8192
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("aperturebridge.web")


def bucket() -> str:
    return os.environ["APP_BUCKET"]


def validate_file(name, content_type, size):
    cleaned = secure_filename(Path(name or "").name)
    if not cleaned or len(cleaned) > 130:
        raise ValueError("A filename (up to 130 safe characters) is required")
    if content_type not in MIME_TYPES:
        raise ValueError("Only JPEG, PNG and WebP images are allowed")
    if not isinstance(size, int) or not 1 <= size <= MAX_BYTES:
        raise ValueError("File must be between 1 byte and 10 MiB")
    return cleaned


def new_asset(name, content_type, size):
    cleaned = validate_file(name, content_type, size)
    uid = str(uuid.uuid4())
    return {"id": uid, "original_name": cleaned,
            "object_key": f"raw/{uid}/{cleaned}", "content_type": content_type, "status": "PENDING"}


@application.get("/")
def index():
    return render_template("index.html", local_proxy=flag("LOCAL_UPLOAD_PROXY"))


@application.get("/healthz")
def healthz():
    return jsonify(status="ok", component="web")


@application.get("/readyz")
def readyz():
    try:
        with get_engine().connect() as con:
            con.execute(text("SELECT 1"))
        return jsonify(status="ready")
    except Exception:
        logger.exception("Database readiness probe failed")
        return jsonify(status="unavailable"), 503


@application.post("/api/uploads/intents")
def create_upload_intent():
    if flag("LOCAL_UPLOAD_PROXY"):
        return jsonify(error="Use /api/uploads/local when running the local demo"), 409
    payload = request.get_json(silent=True) or {}
    try:
        item = new_asset(payload.get("name"), payload.get("content_type"), payload.get("size"))
    except ValueError as exc:
        return jsonify(error=str(exc)), 400
    s3 = aws_client("s3", accelerate=flag("S3_ACCELERATE"))
    # Presigned POST enforces BOTH size range and declared content type.
    post = s3.generate_presigned_post(
        Bucket=bucket(), Key=item["object_key"],
        Fields={"Content-Type": item["content_type"]},
        Conditions=[["content-length-range", 1, MAX_FORM_BYTES],
                    {"Content-Type": item["content_type"]}], ExpiresIn=300,
    )
    with get_engine().begin() as con:
        con.execute(insert(assets).values(**item))
    return jsonify(id=item["id"], upload=post), 201


@application.post("/api/uploads/local")
def local_upload():
    # Intentionally disabled on AWS. Cloud mode streams directly browser -> S3.
    if not flag("LOCAL_UPLOAD_PROXY"):
        return jsonify(error="Local-only endpoint disabled"), 404
    file = request.files.get("file")
    if not file:
        return jsonify(error="No file provided"), 400
    data = file.stream.read(MAX_BYTES + 1)
    try:
        item = new_asset(file.filename, file.mimetype, len(data))
    except ValueError as exc:
        return jsonify(error=str(exc)), 400
    with get_engine().begin() as con:
        con.execute(insert(assets).values(**item))
    try:
        aws_client("s3").put_object(Bucket=bucket(), Key=item["object_key"], Body=data,
                                    ContentType=item["content_type"])
    except Exception:
        with get_engine().begin() as con:
            con.execute(assets.update().where(assets.c.id == item["id"]).values(status="FAILED"))
        raise
    return jsonify(id=item["id"]), 201


@application.get("/api/assets")
def list_assets():
    with get_engine().connect() as con:
        rows = con.execute(select(assets).order_by(assets.c.created_at.desc()).limit(50)).mappings().all()
    s3 = aws_client("s3")
    results = []
    for row in rows:
        entry = {"id": row["id"], "name": row["original_name"], "status": row["status"],
                 "created_at": row["created_at"].isoformat() if row["created_at"] else None}
        if row["status"] == "READY" and row["processed_key"]:
            if flag("LOCAL_UPLOAD_PROXY"):
                entry["preview_url"] = f"/api/assets/{row['id']}/preview"
            else:
                entry["preview_url"] = s3.generate_presigned_url(
                    "get_object", Params={"Bucket": bucket(), "Key": row["processed_key"]}, ExpiresIn=300)
        results.append(entry)
    return jsonify(results)


@application.get("/api/assets/<uuid:asset_id>/preview")
def local_preview(asset_id):
    """Local demo only: bridge container-only LocalStack DNS to browser."""
    if not flag("LOCAL_UPLOAD_PROXY"):
        return jsonify(error="Local-only endpoint disabled"), 404
    with get_engine().connect() as con:
        row = con.execute(select(assets).where(assets.c.id == str(asset_id))).mappings().first()
    if not row or row["status"] != "READY" or not row["processed_key"]:
        return jsonify(error="Image preview not found"), 404
    obj = aws_client("s3").get_object(Bucket=bucket(), Key=row["processed_key"])
    return Response(obj["Body"].read(MAX_BYTES + 1), mimetype="image/jpeg",
                    headers={"Cache-Control": "private, max-age=60"})


@application.errorhandler(413)
def too_large(_):
    return jsonify(error="Maximum upload size is 10 MiB"), 413


@application.errorhandler(Exception)
def unexpected(exc):
    from werkzeug.exceptions import HTTPException
    if isinstance(exc, HTTPException):
        return jsonify(error=exc.description), exc.code
    logger.exception("Unhandled web error")
    return jsonify(error="Unexpected server error. Check application logs."), 500

if __name__ == "__main__":
    application.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), debug=False)
