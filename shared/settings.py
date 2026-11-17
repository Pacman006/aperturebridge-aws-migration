"""Centralized runtime configuration. No access keys or passwords in source code."""
import json
import os
from functools import lru_cache
from urllib.parse import quote_plus
import boto3
from sqlalchemy import create_engine
from sqlalchemy.pool import StaticPool


def flag(name: str, default: bool = False) -> bool:
    return os.getenv(name, str(default)).lower() in ("1", "true", "yes")


def aws_client(service: str, *, accelerate: bool = False):
    from botocore.config import Config
    opts = {"region_name": os.getenv("AWS_REGION", "ap-south-1")}
    endpoint = os.getenv("AWS_ENDPOINT_URL")  # local emulator only
    if endpoint:
        opts["endpoint_url"] = endpoint
    if accelerate and not endpoint:
        opts["config"] = Config(s3={"use_accelerate_endpoint": True}, signature_version="s3v4")
    return boto3.client(service, **opts)


@lru_cache(maxsize=2)
def db_identity(admin: bool = False) -> tuple[str, str]:
    arn = os.environ.get("DB_ADMIN_SECRET_ARN" if admin else "DB_SECRET_ARN", "")
    if arn:
        payload = aws_client("secretsmanager").get_secret_value(SecretId=arn)["SecretString"]
        secret = json.loads(payload)
        return secret["username"], secret["password"]
    if admin:
        raise RuntimeError("DB_ADMIN_SECRET_ARN must be set for schema bootstrap")
    return os.getenv("DB_USER", "aperture_app"), os.getenv("DB_PASSWORD", "")


@lru_cache(maxsize=2)
def get_engine(admin: bool = False):
    # SQLite is ONLY for isolated unit tests; never use it as the cloud database.
    if not admin and os.getenv("TEST_DATABASE_URL"):
        url = os.environ["TEST_DATABASE_URL"]
        return create_engine(url, poolclass=StaticPool if ":memory:" in url else None,
                             connect_args={"check_same_thread": False} if ":memory:" in url else {})
    user, password = db_identity(admin)
    host = os.environ["DB_HOST"]
    db_name = os.getenv("DB_NAME", "aperturebridge")
    port = os.getenv("DB_PORT", "3306")
    url = f"mysql+pymysql://{quote_plus(user)}:{quote_plus(password)}@{host}:{port}/{db_name}?charset=utf8mb4"
    tls_ca = os.getenv("DB_TLS_CA")
    kwargs = {"connect_args": {"ssl": {"ca": tls_ca, "check_hostname": True}}} if tls_ca else {}
    return create_engine(url, pool_pre_ping=True, pool_recycle=1200, pool_size=3, max_overflow=2, **kwargs)
