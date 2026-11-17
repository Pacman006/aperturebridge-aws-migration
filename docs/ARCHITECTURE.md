# Architecture and engineering decisions

## Source-derived context vs designed replacement

The 2018 course brief specifies a single on-premises host holding a front-end, back-end processor, MySQL and uploaded images. It requires a stage-1 container, S3 upload change and OVA export followed by EC2, EB, Aurora, ECR/ECS and S3 Transfer Acceleration. It does **not** define a web framework, data schema, image processing algorithm, RTO/RPO, allowed downtime, identity provider, existing host OS, code repository or even the size of the image archive.

The following are explicit **design assumptions**, not facts about the original company: Python/Flask, JPG/PNG/WebP inputs, 10 MiB application limit, JPEG previews with maximum 720 px longest edge, metadata in the `assets` table, lifecycle statuses `PENDING → READY|REJECTED|FAILED`, 7-day Aurora backup retention and sample region `ap-south-1`.

## Key architecture decisions

| Decision | Why | Trade-off / improvement |
|---|---|---|
| Elastic Beanstalk on Python 3.12 AL2023 for web | The assignment explicitly requests EB; managed platform/ALB and scaling | For new greenfield workloads, ECS/App Runner may reduce platform diversity, but would not meet the assignment literally |
| S3 presigned POST directly from browser | Large bytes bypass the web tier; short-lived object-specific uploads with POST size conditions | Auth and rate limiting must be in front of intent API; pending uploads should be garbage-collected |
| S3 → SQS Standard → ECS Fargate worker | Independent scaling and retry isolation, no instance administration | S3 messages can duplicate or arrive out of order; consumer uses idempotent deterministic output keys |
| SQS DLQ after five attempts | Poison messages do not halt the queue | Provide alarm + redrive workflow after root cause is fixed |
| Aurora MySQL (private) with separate application credential | Breaks single-host failure domain and restricts database network | A full production design needs at least two DB instances and tested failover RTO |
| Temporary imported EC2 with public IP, no inbound rules | Satisfies migration exercise without turning a legacy OS into a public entry point | SSM access requires supported OS, SSM Agent/role/connectivity; imported appliance may not be supported |
| S3 Transfer Acceleration | Explicit assignment requirement, useful for long-distance uploads | Test transfer performance/cost, DNS-safe dotless bucket, enable in supported region |
| Two app AZs, one NAT in lab | Efficient, understandable demonstration | A production HA design needs one NAT per AZ or alternate egress design |
| S3 SSE-S3 and blocked public access | Simple managed at-rest protection | Policy-based KMS keys/rotation and compliance mapping may be needed |

## Application protocol and failure management

1. Browser requests `/api/uploads/intents` over TLS. Frontend checks declared MIME, size and name, generates UUID, and obtains a 5-minute signed S3 POST policy (key scoped under `raw/<uuid>/`). It inserts a `PENDING` database row.
2. Browser sends bytes straight to the accelerate S3 HTTPS endpoint using generated fields. Post conditions limit declared content type and upload form size. The bucket remains private.
3. S3 issues an ObjectCreated notification for `raw/`. Queue's resource policy permits **only** the configured bucket/account to publish; the queue has SQS-managed encryption and a DLQ.
4. Worker polls SQS long-poll, retrieves object from private S3, verifies Pillow's decoded image format, rejects oversized/decompression-bomb images, strips metadata by re-encoding, creates `processed/<uuid>/preview.jpg`.
5. Worker updates `assets.status=READY`; duplicate deliveries simply return `already_done`. A failure before DB commit can safely overwrite the same preview key and retry.
6. The frontend returns metadata and a short-lived presigned **GET** URL for processed previews. Raw images are never made public.

### Known race and edge cases

- The metadata insert occurs **before** the object PUT; worker does not normally see a key without a row. Worker raises/retries if a record is absent, rather than silently losing it.
- S3 events can arrive more than once. Status gating and deterministic processed keys handle sequential duplicates; simultaneous duplicates can redo work safely, though they incur extra compute and extra S3 versions.
- A user can abandon an intent leaving `PENDING`. A scheduled expiry job and upload idempotency tokens are production backlog items.
- Browser file type and size are preliminary. Server creates a POST policy with size and type limits, and worker independently verifies actual content. The signed policy permits 8 KiB of multipart/form overhead beyond the 10 MiB file limit; the worker independently caps the actual image at 10 MiB. Recheck POST semantics against AWS in the live acceptance test.
- Worker retries transient AWS/DB failures and sends unresolved messages to a DLQ; invalid image content is marked `REJECTED` and acknowledged.
- Database connections are protected by TLS with a downloaded RDS trust bundle and validation enabled in cloud mode. Application secrets are fetched by scoped IAM roles.
- An expired preview URL simply requires a fresh `/api/assets` call.

## Production readiness gaps (deliberately not concealed)

A secure internal reference design does **not** imply this lab is ready for anonymous public internet traffic. Before deploying to real users, add Cognito/OIDC identity and tenant ownership checks, AWS WAF/bot rate limits and quotas, malware scanning/quarantine, encryption policy/KMS as mandated, ALB HTTPS redirect, custom domain and DNS failover, automated stale-intent cleanup, alerting on SQS DLQ + Aurora performance + 5xx rates, cross-account immutable backups, multi-AZ DB instances, image retention policies, and load testing. Replace wildcard lab CORS with the exact HTTPS origin. Migrate Terraform state to an encrypted, access-controlled backend with locking. Run a security review and penetration test against actual endpoints.

## Migration topology nuance

Imported VM and new microservices must **not** both serve live writes against diverging databases during cutover. Use CDC/migration synchronization while the old system remains authoritative. Freeze writes, wait for replication lag to zero, reconcile rows/files, switch traffic and keep a read-only rollback copy for the approved window. After the new system accepts writes, rolling back to a stale legacy database requires an explicit reverse-replication/data-loss strategy; it is not a safe one-click DNS flip.
