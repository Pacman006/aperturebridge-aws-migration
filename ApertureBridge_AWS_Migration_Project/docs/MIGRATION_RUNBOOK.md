# Migration runbook — existing image-hosting VM to AWS

**Owner:** migration lead + app owner + DBA + security approver. **Strategy:** rehost legacy VM temporarily (required by assignment), replatform web and DB, refactor backend into ECS, and relocate binary objects to S3. No real source VM, database, image archive, DNS zone or downtime approval was supplied. The execution boxes below must remain **unverified** until an operator attaches evidence from the actual environment.

## 0. Discovery, scope and gates

Collect: current VM hostname, OS/kernel, UEFI/BIOS boot mode, virtual disk layout, CPU/RAM/IOPS, hypervisor version, web framework, service ports, SSL endpoints, DB engine/version, DB schema and constraints, users/grants, binlog retention, image volume size/count, disk file paths, upload and retrieval URL contracts, email/CDN endpoints, data sensitivity, backup jobs, DNS TTL, expected peaks, RPO, RTO and outage window. Identify nonportable drivers, hardcoded filesystem paths, MySQL local socket dependencies and synchronous in-process image handling.

**No-go conditions:** untested backup restore; invalid/incompatible OVA; undocumented schema; insufficient permissions; unsupported Aurora MySQL source version; no rollback plan; diverging writes with no replication; missing owner approval or budget.

## 1. Source system baseline

1. Record uptime, CPU, disk free space, open listeners and process startup mechanism.
2. Run `sql/dms-source-precheck.sql` against **source** MySQL. Save schema-only dump, row counts per table, relationship graph and a secured full backup. Never commit SQL dumps containing live records.
3. Produce an image inventory CSV with stable `legacy_id`, absolute or relative `local_path`, `filename`, `content_type`. Example is `scripts/legacy-manifest.example.csv`. Compute a SHA-256 inventory and total file bytes independently.
4. Document legacy HTTP endpoints, expected content and image rendering rules; the provided Flask example cannot silently replace behavior unknown from the PDF.
5. Create a controlled test VM copy. All destructive tests must run on a clone.

## 2. Stage 1 — container backend, change S3 uploads, export OVA

**Backend:** review the legacy processing program with developers. Rewrite external dependencies into environment variables and IAM-based AWS SDK calls; use `worker/Dockerfile` and `worker/processor.py` as the *reference*. Build locally:

```powershell
docker build --platform linux/amd64 -f worker/Dockerfile -t aperturebridge-worker:lab .
```

**Website uploads:** change the page to request a short-lived presigned S3 POST, use the POST policy and make the asset record `PENDING`; poll until the processor sets `READY`. Demonstration path is implemented in `frontend/application.py`, with a local-only proxy mode for Docker Compose. Store no S3 access key in browser JavaScript.

**OVA export:** isolate and quiesce the VM. Prefer snapshot/backup first and shut down cleanly before export. On VirtualBox, use *File → Export Appliance* and select OVA with the required disk(s). On VMware, use the vendor-supported OVF Tool / export appliance process as appropriate. Record source VM configuration, number of disks, OVA SHA-256, export logs and whether the OS/boot mode is supported by VM Import/Export. Confirm the OVA contains needed guest data, not just an empty shell; `tar -tf FILE.ova` can inspect a tar-based OVA's contents. This repository **cannot create a real OVA without source VM disks**.

## 3. Stage 2 — build the landing zone

Run Terraform from `docs/DEPLOY_WINDOWS.md`. Inspect the 2-AZ VPC, egress routes, ALB/EB instance SGs, isolated Aurora SG, IAM task/instance roles, private S3 bucket, accelerated endpoint, SQS/DLQ, private ECR and ECS cluster. Cloud costs begin at creation.

## 4. Import the OVA to EC2 (separate rehost step)

Required: account-appropriate `vmimport` service role and caller permissions including `iam:PassRole`; an eligible guest OS/license; compatible partition/boot configuration; import bucket access, STS enabled in region. AWS has specific restrictions on imported images—verify them before starting. The Terraform project creates the `vmimport` role; if this global IAM role already exists, import/manage it rather than trying to create a duplicate.

```powershell
.\scripts\06-Import-LegacyVM.ps1 -OvaPath 'D:\secure\ABC-Legacy-2026.ova' -LicenseType AWS
```

The script uploads the OVA to the **private import S3 bucket**, starts `ec2 import-image`, waits for an AMI, launches a temporary EC2 in the **public subnet** with an automatically assigned public IPv4 address and the restricted legacy SG. **No inbound TCP 22/80/443 rule is created**: use Systems Manager Session Manager to inspect the host (requires supported agent and connectivity). A public IP by itself does not expose the application. Verify EC2 ID, instance health, software and filesystem. Keep the original server authoritative until cutover. Terminate the imported VM after approved acceptance and expiry of the rollback window.

**Important:** the imported EC2 instance is created by the **script** and is therefore **not Terraform-managed**. Record its instance ID and terminate manually during cleanup.

## 5. MySQL → Aurora MySQL (data migration, not just target provisioning)

**Small database with a planned outage:** `mysqldump --single-transaction --routines --triggers --events --set-gtid-purged=OFF` from a supported MySQL engine, followed by an Aurora restore. Validate charset/collation, users, events and consistency. If data volume or outage tolerance requires continuous replication, use AWS Database Migration Service (DMS) *full load plus CDC* / homogeneous migration capabilities, guided by the current source-engine compatibility matrix.

**DMS high-level sequence (operator-controlled):**

1. Enable MySQL binary logging on source (`log_bin=ON`, `server_id>=1`, `binlog_format=ROW`, `binlog_row_image=FULL`) and maintain retention until cutover. Restart if needed and recheck with `sql/dms-source-precheck.sql`.
2. Create a dedicated DMS source user with narrowly scoped `SELECT`, `REPLICATION CLIENT`, `REPLICATION SLAVE` (current AWS DMS manual specifies these for CDC); protect its credentials. Do not expose MySQL 3306 on the public internet. Connect through VPN/Direct Connect/private VPC or a restrictive temporary rule.
3. Precreate an **operator-chosen `legacy_abc` database/schema** on the Aurora target to keep legacy structures distinct from this demo's new `aperturebridge.assets` table. Have the DBA review schema compatibility, triggers, keys, auto-increment, stored procedures and schema DDL that AWS DMS may not transfer.
4. Create DMS source/target endpoints, replication instance or DMS serverless configuration in approved private subnets. Use TLS connections and verify endpoints. The source endpoint is the existing MySQL VM; the destination is the Aurora writer endpoint from Terraform outputs.
5. Start full load and CDC or a homogeneous migration task; select specific schemas/tables and a target table prep mode that does **not** destroy an existing production schema. Watch full-load table status, task logs, binlog lag and errors. Do not start production writes to the new system yet.
6. Validate **row counts, primary keys, NULL semantics, charset/collation, UTC timestamps, foreign keys, stored routines, sample records, checksums where possible**. Inventory tables that DMS may not migrate, and migrate them separately.
7. At cutover: freeze old writes, wait for CDC lag zero, reconcile delta, validate image manifests, switch web route, then enable new writes and monitor.

**Application mapping:** the reference `aperturebridge.assets` schema is new. The assignment does not reveal the legacy table design; there is no safe way to claim automatic field mapping. Use `sql/legacy-to-new-mapping.example.sql` as an explicit review placeholder and the image manifest backfill tool once the owner defines source IDs and file paths.

## 6. Move historical images with S3 Transfer Acceleration

The target bucket is dotless, versioned and acceleration-enabled. For an existing data set under a reachable VM filesystem, use the provided script. **Run it from a VPC-connected host** such as the imported VM after temporarily granting the minimum required app Secret, S3 `PutObject raw/*` permissions and DB SG source rule. You must also install Python dependencies and download the RDS global trust bundle from AWS.

```bash
# Example commands INSIDE a Linux migration VM, run from the cloned repository:
python3 -m venv venv
./venv/bin/pip install boto3 sqlalchemy pymysql cryptography werkzeug
curl -fsSLo /tmp/rds-global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
export AWS_REGION=ap-south-1
export APP_BUCKET='<from terraform output assets_bucket>'
export DB_HOST='<from terraform output aurora_writer_endpoint>'
export DB_NAME=aperturebridge
export DB_SECRET_ARN='<from terraform output app_secret_arn>'
export DB_TLS_CA=/tmp/rds-global-bundle.pem
./venv/bin/python scripts/07-Backfill-Legacy.py --manifest scripts/legacy-manifest.example.csv --root /var/abc --dry-run
./venv/bin/python scripts/07-Backfill-Legacy.py --manifest /secure/approved-manifest.csv --root /var/abc
```

The script derives stable UUIDs from `legacy_id`, inserts metadata first, and then uploads each local file to `raw/<uuid>/<filename>` with boto3's **accelerated S3 endpoint**. This causes S3 event messages and ECS processing. It is safe to rerun after a partial failure for the same legacy IDs. Rejects missing/empty files, unsupported MIME and files over the demo app's 10 MiB policy; production migrations may require a separate large-file pipeline. Do **not** check the manifest with actual customer locations/identifiers into public GitHub.

**Validation:** compare counts of eligible images from inventory to count of `READY` rows; compare original size and SHA-256 where required using a separate controlled audit job, inspect SQS/DLQ depths, and spot-check original bytes and thumbnails. S3 Transfer Acceleration makes sense mainly for significant long-distance paths; run the AWS speed comparison tool and assess incremental costs. It does not magically speed every within-region upload.

## 7. Deploy ECR / ECS and Elastic Beanstalk

Run scripts in the exact order in `docs/DEPLOY_WINDOWS.md`: Terraform foundation → ECR image push → Terraform image tag → one-off schema task → start ECS worker → publish EB frontend. In production use a domain with TLS and customer authentication. Local image screenshots and synthetic data are not acceptance evidence for a live migration.

## 8. Cutover acceptance, rollback, decommission

Use [ACCEPTANCE_AND_ROLLBACK.md](ACCEPTANCE_AND_ROLLBACK.md). Do not remove source binlogs, snapshots or image backups until reconciliation is formally signed off. Once the new database accepts writes, rollback must account for reverse changes (otherwise there is potential data loss); DNS-only rollback is insufficient. Terminate extra imported EC2 and DMS jobs, revoke temporary IAM/3306 permissions, disable unused secrets, and update documentation with final costs, approvals and change tickets.
