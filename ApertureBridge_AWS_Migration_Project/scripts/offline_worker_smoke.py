"""Dependency-light worker smoke test using in-memory S3 + SQLite.

Run from project root: python scripts/offline_worker_smoke.py
Requires SQLAlchemy and Pillow (and boto3 imported by runtime module), no AWS credentials.
"""
import io
import json
import uuid
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from PIL import Image
from sqlalchemy import create_engine, insert, select
from sqlalchemy.pool import StaticPool
from shared.models import metadata, assets
import worker.processor as processor

class FakeS3:
    def __init__(self): self.items = {}
    def get_object(self, Bucket, Key): return {"Body": io.BytesIO(self.items[(Bucket, Key)])}
    def put_object(self, Bucket, Key, Body, ContentType=None):
        self.items[(Bucket, Key)] = Body
        return {"ETag": "local"}


def main():
    engine = create_engine('sqlite:///:memory:', poolclass=StaticPool)
    metadata.create_all(engine)
    s3 = FakeS3()
    processor.get_engine = lambda: engine
    processor.aws_client = lambda service: s3
    bucket = 'offline-test-bucket'
    image = io.BytesIO()
    Image.new('RGB', (1500, 1000), (37, 118, 179)).save(image, format='PNG')
    ids = [str(uuid.uuid4()) for _ in range(2)]
    keys = [f'raw/{ids[0]}/valid.png', f'raw/{ids[1]}/invalid.png']
    with engine.begin() as con:
        for uid, key in zip(ids, keys):
            con.execute(insert(assets).values(id=uid, object_key=key,
                  original_name=key.split('/')[-1], content_type='image/png', status='PENDING'))
    s3.items[(bucket, keys[0])] = image.getvalue()
    s3.items[(bucket, keys[1])] = b'not a png'
    assert processor.process_object(bucket, keys[0]) == 'ready'
    with engine.connect() as con:
        one = con.execute(select(assets).where(assets.c.id == ids[0])).mappings().one()
    assert one['status'] == 'READY'
    assert one['processed_key'] == f'processed/{ids[0]}/preview.jpg'
    with Image.open(io.BytesIO(s3.items[(bucket, one['processed_key'])])) as thumb:
        assert thumb.width <= 720 and thumb.format == 'JPEG'
    assert processor.process_object(bucket, keys[0]) == 'already_done'
    assert processor.process_object(bucket, keys[1]) == 'rejected'
    with engine.connect() as con:
        two = con.execute(select(assets).where(assets.c.id == ids[1])).mappings().one()
    assert two['status'] == 'REJECTED'
    try:
        processor.process_object(bucket, f'raw/{uuid.uuid4()}/missing.png')
        assert False, 'missing asset metadata should retry rather than acknowledge'
    except LookupError: pass
    assert processor.process_object(bucket, 'processed/not-raw') == 'skipped'
    processor.process_message({'Body': json.dumps({'Event': 's3:TestEvent'})})
    try:
        processor.make_thumbnail(b'x' * (10 * 1024 * 1024 + 1))
        assert False, 'oversized object should reject'
    except ValueError: pass
    print('PASS: image processing, JPEG dimensions, deterministic key, duplicate delivery, corrupt image,')
    print('      missing metadata retry, non-raw filtering, S3 test event, oversized image cap')

if __name__ == '__main__':
    main()
