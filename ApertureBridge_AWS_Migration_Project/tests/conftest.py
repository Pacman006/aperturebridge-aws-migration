import os
import pytest
from moto import mock_aws
from shared.models import metadata
from shared.settings import get_engine, db_identity

@pytest.fixture
def sandbox(monkeypatch):
    env = {
        'AWS_REGION': 'ap-south-1', 'AWS_DEFAULT_REGION': 'ap-south-1',
        'AWS_ACCESS_KEY_ID': 'testing', 'AWS_SECRET_ACCESS_KEY': 'testing',
        'APP_BUCKET': 'aperturebridge-test-bucket',
        'TEST_DATABASE_URL': 'sqlite+pysqlite:///:memory:',
        'S3_ACCELERATE': 'false', 'LOCAL_UPLOAD_PROXY': 'true',
    }
    for key, val in env.items(): monkeypatch.setenv(key, val)
    for key in ('DB_SECRET_ARN','DB_ADMIN_SECRET_ARN','AWS_ENDPOINT_URL','DB_TLS_CA'):
        monkeypatch.delenv(key, raising=False)
    get_engine.cache_clear()
    db_identity.cache_clear()
    with mock_aws():
        from shared.settings import aws_client
        aws_client('s3').create_bucket(
            Bucket='aperturebridge-test-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'ap-south-1'},
        )
        metadata.create_all(get_engine())
        yield
    get_engine.cache_clear()
    db_identity.cache_clear()
