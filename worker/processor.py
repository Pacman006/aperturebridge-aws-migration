"""S3 ObjectCreated -> SQS -> ECS thumbnail worker (idempotent, retry-safe)."""
import io
import json
import logging
import os
import time
from datetime import datetime, timezone
from urllib.parse import unquote_plus
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import select, update
from shared.models import assets
from shared.settings import aws_client, get_engine

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("aperturebridge.worker")
Image.MAX_IMAGE_PIXELS = 20_000_000
MAX_BYTES = 10 * 1024 * 1024


def make_thumbnail(raw: bytes) -> bytes:
    if len(raw) > MAX_BYTES:
        raise ValueError("Object exceeds maximum size")
    with Image.open(io.BytesIO(raw)) as photo:
        photo.verify()
    with Image.open(io.BytesIO(raw)) as photo:
        image = ImageOps.exif_transpose(photo)
        if image.width * image.height > 20_000_000:
            raise ValueError("Image dimensions exceed safety limit")
        image.thumbnail((720, 720))
        if image.mode not in ("RGB", "L"):
            image = image.convert("RGB")
        result = io.BytesIO()
        image.save(result, format="JPEG", quality=82, optimize=True)
        return result.getvalue()


def process_object(bucket: str, key: str) -> str:
    if not key.startswith("raw/"):
        return "skipped"
    engine = get_engine()
    with engine.connect() as con:
        row = con.execute(select(assets).where(assets.c.object_key == key)).mappings().first()
    if not row:
        # Retry rather than drop a newly arrived event whose DB write may be delayed.
        raise LookupError(f"No metadata for {key}")
    if row["status"] == "READY":
        return "already_done"
    s3 = aws_client("s3")
    try:
        obj = s3.get_object(Bucket=bucket, Key=key)
        raw = obj["Body"].read(MAX_BYTES + 1)
        output = make_thumbnail(raw)
    except (UnidentifiedImageError, ValueError, Image.DecompressionBombError, OSError) as exc:
        logger.warning("Rejected image %s: %s", row["id"], exc)
        with engine.begin() as con:
            con.execute(update(assets).where(assets.c.id == row["id"]).values(
                status="REJECTED", error_message="Unsupported or unsafe image"))
        return "rejected"
    processed_key = f"processed/{row['id']}/preview.jpg"
    # Deterministic key makes duplicate events safe, even after a crash between S3 and DB.
    s3.put_object(Bucket=bucket, Key=processed_key, Body=output, ContentType="image/jpeg")
    with engine.begin() as con:
        con.execute(update(assets).where(assets.c.id == row["id"]).values(
            processed_key=processed_key, status="READY", processed_at=datetime.now(timezone.utc).replace(tzinfo=None)))
    logger.info("Processed asset %s -> %s", row["id"], processed_key)
    return "ready"


def process_message(message: dict) -> None:
    payload = json.loads(message["Body"])
    if payload.get("Event") == "s3:TestEvent":
        return
    for record in payload.get("Records", []):
        if not record.get("eventName", "").startswith("ObjectCreated:"):
            continue
        location = record["s3"]
        process_object(location["bucket"]["name"], unquote_plus(location["object"]["key"]))


def run_forever():
    queue_url = os.environ["SQS_QUEUE_URL"]
    sqs = aws_client("sqs")
    logger.info("SQS worker started; polling queue")
    while True:
        response = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=5,
                                       WaitTimeSeconds=20, VisibilityTimeout=180)
        for msg in response.get("Messages", []):
            try:
                process_message(msg)
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=msg["ReceiptHandle"])
            except Exception:
                logger.exception("Processing failed; leaving message for retry / eventual DLQ")


if __name__ == "__main__":
    run_forever()
