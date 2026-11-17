# Test, cutover and rollback acceptance

No production verification can occur without an AWS account, real company source assets, RPO/RTO agreement and approval. The following is a **test protocol**, not a record of tests passed in AWS.

## Acceptance gates

| # | Test / evidence | Expected acceptance result | Owner |
|---|---|---|---|
| A01 | `terraform fmt -check` + `terraform validate` | Exit code 0, no unknown provider argument | Cloud engineer |
| A02 | Python tests in GitHub Actions | All unit tests green | Developer |
| A03 | Full local `docker compose up` + image upload | Asset goes `PENDING → READY`; browser shows JPEG thumbnail | Developer |
| A04 | Source inventory and OVA export | Approved OVA checksum and bootable VM clone | Migration engineer |
| A05 | EC2 import as AMI + launch | Import `completed`, instance healthy, public IP assigned, no SG ingress | Cloud engineer |
| A06 | MySQL schema/row reconciliation | Approved row count + sample compare; CDC lag within cutover threshold | DBA |
| A07 | S3 backfill inventory | Eligible image counts matched; no unexplained missing objects | Migration engineer |
| A08 | Aurora private network | No route from internet to DB; only approved SG sources reach 3306 | Security |
| A09 | Backend ECS service | Task `RUNNING`, image pulled from ECR, CloudWatch logs work | Operations |
| A10 | EB web deployment | EB healthy, `/healthz` and `/readyz` HTTP 200 | Operations |
| A11 | Browser upload (valid and corrupt) | Valid `READY`; corrupt `REJECTED`; no public bucket | QA |
| A12 | SQS redelivery / DLQ | Transient failure retried; poison event visible in DLQ | QA/SRE |
| A13 | HTTPS + domain | Valid certificate, TLS 1.2+/modern TLS, correct CORS, no unauthenticated access | Security |
| A14 | Aurora backup and recovery drill | Restored snapshot, verified data and documented recovery time | DBA/SRE |
| A15 | Planned DNS cutover and rollback decision | Business sign-off and immutable evidence record | Change manager |

## Test datasets

Use a 1x1 JPEG, a 5 MiB PNG, a transparent WebP, EXIF-rotated JPEG, a renamed nonimage (`.png` containing text), and a file larger than configured limit. Verify pixel dimensions and stripping of source EXIF in generated JPEG. Try duplicate S3 event messages and restart worker between S3 preview upload and Aurora update (should reprocess to same key). Confirm CORS with the actual custom HTTPS origin—emulators cannot prove AWS browser compatibility.

## Cutover procedure (only after gates pass)

**T-72 hours:** record approved change window, alert routing, DNS TTL, backups/snapshots and rollback owner; verify old application remains operational and replication healthy.

**T-24 hours:** re-run inventory, DB full-load/CDC checks, asset count and preview sample tests; clear nonessential queued backlog; capture export checksums and AWS resource IDs.

**T-1 hour:** freeze destructive source schema changes; warm up target; create fresh source snapshot and a rollback ledger of source/target data boundaries. Obtain final GO/NO-GO sign-off.

**T0:** restrict source writes, wait for DMS CDC lag to zero, reconcile final binlog/image deltas, verify old upload queue drained, then switch DNS / external ingress to the new HTTPS host. Run controlled test users; watch 4xx/5xx, ALB target health, Aurora CPU/connections, ECS task restarts, SQS queue age, DLQ and object counts. Resume customer writes only after validation.

**T+1–24 hours:** observe error budget and throughput, compare metadata/object count changes, retain source systems read-only, perform sampled customer-flow checks, and establish a documented end of rollback window.

**T+N days (approved):** archive source backups, terminate old VM/DMS, revoke temporary access and update cost/ownership inventory. Make sure backup retention policy was formally agreed.

## Rollback decision tree

- **Before target accepts writes:** revert DNS/ALB traffic to original service if source DB/files are still authoritative and healthy. Run smoke checks and document the incident.
- **After target accepts writes:** never roll back to an old source database without controlled reverse synchronization (new rows/images written to target would be lost). Trigger incident command, suspend new writes, preserve Aurora snapshots/binlogs and S3 object versions, decide whether forward-fix is safer, and have DBA explicitly assess reverse migration plus conflict resolution.
- **Bad worker release only:** stop ECS desired count, pin previous ECR **immutable** tag in Terraform, apply, validate SQS redelivery; web can continue to accept uploads temporarily if queue and retention allow.
- **Bad EB release only:** deploy prior known-good Beanstalk application version. That does not revert irreversible database schema migrations, so use backward-compatible database changes.

## Evidence and sign-off template

Record a change ticket with tested commit SHA, Terraform state version, AWS account/region (internal ticket only), exported OVA checksum, source and target row counts, failed object list, DMS status/CDC lag, CloudWatch dashboard links, screenshot of health and upload flow, backup ID, decision timestamp, named technical/business approvers, rollback test and cost estimate. Do not put sensitive evidence into a public GitHub repository.
