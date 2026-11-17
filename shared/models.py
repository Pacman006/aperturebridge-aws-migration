"""Explicit relational schema, consistent across MySQL 8/Aurora and SQLite tests."""
from sqlalchemy import MetaData, Table, Column, String, DateTime, func

metadata = MetaData()
assets = Table(
    "assets", metadata,
    Column("id", String(36), primary_key=True),
    Column("original_name", String(255), nullable=False),
    Column("object_key", String(512), nullable=False, unique=True),
    Column("content_type", String(80), nullable=False),
    Column("status", String(20), nullable=False, default="PENDING"),
    Column("processed_key", String(512), nullable=True),
    Column("error_message", String(255), nullable=True),
    Column("created_at", DateTime, server_default=func.current_timestamp()),
    Column("processed_at", DateTime, nullable=True),
)
