"""Run from a host with VPC access to Aurora (e.g. imported EC2 via SSM).

CSV required columns: legacy_id,local_path,filename,content_type
Sample: old-001,/var/legacy/uploads/beach.jpg,beach.jpg,image/jpeg
Set APP_BUCKET, DB_HOST, DB_NAME, DB_SECRET_ARN, DB_TLS_CA, AWS_REGION.
Use the EC2 instance role; never paste credentials or secrets into source code.
"""
import argparse
import csv
import logging
import os
import sys
import uuid
from pathlib import Path
# Ensure `shared/` imports work when invoked as a script on the migration VM.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sqlalchemy import insert, select
from werkzeug.utils import secure_filename
from shared.models import assets
from shared.settings import aws_client, get_engine

logging.basicConfig(level=logging.INFO, format='%(levelname)s %(message)s')
log = logging.getLogger('backfill')
BATCH_NAMESPACE = uuid.UUID('3f7319b7-28dc-4b30-815e-0fd5a3d628a8')
ALLOWED_MIME = {'image/png', 'image/jpeg', 'image/webp'}
MAX_BYTES = 10 * 1024 * 1024


def backfill_row(row, root, dry_run=False):
    legacy_id = row['legacy_id'].strip()
    name = secure_filename(row['filename'])
    mime = row['content_type'].strip()
    if not legacy_id or not name or mime not in ALLOWED_MIME:
        raise ValueError(f'Invalid legacy metadata for ID {legacy_id!r}')
    approved_root = root.resolve()
    full = (approved_root / row['local_path']).resolve()
    if approved_root not in full.parents:
        raise ValueError(f'Legacy image path escapes approved root: {full}')
    if not full.is_file() or full.stat().st_size > MAX_BYTES or full.stat().st_size == 0:
        raise ValueError(f'Missing, empty or oversized legacy image: {full}')
    uid = str(uuid.uuid5(BATCH_NAMESPACE, legacy_id))
    key = f'raw/{uid}/{name}'
    if dry_run:
        log.info('DRY RUN %s -> s3://%s/%s', full, os.environ['APP_BUCKET'], key)
        return
    engine = get_engine()
    with engine.begin() as con:
        existing = con.execute(select(assets.c.object_key).where(assets.c.id == uid)).first()
        if existing and existing[0] != key:
            raise ValueError(f'Legacy ID {legacy_id!r} maps to multiple filenames; review manifest')
        if not existing:
            con.execute(insert(assets).values(id=uid, original_name=name,
                object_key=key, content_type=mime, status='PENDING'))
    s3 = aws_client('s3', accelerate=True)
    s3.upload_file(str(full), os.environ['APP_BUCKET'], key, ExtraArgs={'ContentType': mime})
    log.info('Uploaded %s -> %s', legacy_id, key)


def main():
    parser = argparse.ArgumentParser(description='Idempotent legacy image transfer and metadata indexing')
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--root', type=Path, default=Path('.'))
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    failures = 0
    with args.manifest.open(newline='', encoding='utf-8-sig') as source:
        for line, row in enumerate(csv.DictReader(source), start=2):
            try:
                backfill_row(row, args.root.resolve(), args.dry_run)
            except Exception as exc:
                failures += 1
                log.error('row %d: %s', line, exc)
    if failures:
        raise SystemExit(f'{failures} image(s) failed; fix manifest and rerun')

if __name__ == '__main__':
    main()
