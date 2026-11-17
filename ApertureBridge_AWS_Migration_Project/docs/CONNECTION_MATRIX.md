# Connection and network matrix

## Address space / routing

| Subnet role | AZ A | AZ B | Route to Internet? | Workloads |
|---|---|---|---|---|
| Public | `10.32.0.0/24` | `10.32.1.0/24` | IGW `0.0.0.0/0` | EB-managed ALB, NAT(s), temporary imported EC2 |
| Private app | `10.32.10.0/24` | `10.32.11.0/24` | NAT for general outbound; gateway endpoint for S3 | EB EC2, ECS Fargate |
| Isolated DB | `10.32.20.0/24` | `10.32.21.0/24` | **No** 0/0 route | Aurora writer + DB subnet group |

Terraform uses `var.vpc_cidr` and `cidrsubnet` index 0,1,10,11,20,21. Use a nonoverlapping VPC range for real hybrid connectivity; never connect a new VPN/Direct Connect without checking source CIDRs.

## Exact logical flows

| From | Destination | Port/protocol | IAM / security boundary | Purpose |
|---|---|---|---|---|
| Internet browser | EB-managed ALB | `443/TCP HTTPS` **production**; `80/TCP HTTP` **lab only** | Public ALB SG restricted to active listener | Frontend + API |
| ALB SG | EB web SG | `80/TCP HTTP` inside VPC | SG referencing SG | Reverse proxy to Flask/Gunicorn |
| Browser | S3 Transfer Acceleration | `443/TCP HTTPS` | POST policy scopes object key, max form size, short expiry | Image bytes bypass app servers |
| EB web SG | Aurora DB SG | `3306/TCP MySQL/TLS` | DB SG only web and worker sources; app MySQL user | New metadata, list assets |
| ECS worker SG | Aurora DB SG | `3306/TCP MySQL/TLS` | Task role access to app secret; SQL GRANT SELECT/INSERT/UPDATE | Status updates |
| S3 bucket | SQS Standard | AWS service integration (internal AWS API) | Queue policy checks `aws:SourceArn` and `aws:SourceAccount` | `raw/` ObjectCreated only |
| ECS worker | SQS | `443/TCP HTTPS` | `ReceiveMessage`, `DeleteMessage`, `ChangeMessageVisibility` | Consume events |
| ECS worker | S3 | `443/TCP HTTPS` via VPC endpoint | `GetObject raw/*`, `PutObject processed/*` | Thumbnail processing |
| Web/worker | Secrets Manager | `443/TCP HTTPS` via NAT | Each role may read **only** app secret | SQL credential retrieval |
| Schema one-off ECS | Secrets Manager | `443/TCP HTTPS` via NAT | One-off role may read app + Aurora admin secret | Create tables + SQL user |
| ECS execution agent | ECR API + ECR registry | `443/TCP HTTPS` via NAT | `AmazonECSTaskExecutionRolePolicy` | Pull container image |
| EB instance + ECS worker | CloudWatch Logs / AWS APIs | `443/TCP HTTPS` via NAT | EB/platform and ECS execution role | Logging and telemetry |
| Migrated legacy EC2 | AWS SSM control plane | `443/TCP HTTPS` via IGW | `AmazonSSMManagedInstanceCore`, **no inbound SG** | Interactive validation |
| Temporary source host | S3 accelerated endpoint | `443/TCP HTTPS` | Scope AWS role to `raw/`, use S3 accelerate configuration | Historical image backfill |

**Security group implication:** SG state tracking allows return traffic. The Aurora DB SG has no general-purpose ingress; there is no public DB endpoint. The imported VM SG has zero inbound rules, so public IP assignment does **not** expose SSH or HTTP to the internet. All app and worker communication is outbound initiated; ECS worker has no listener.

## IAM roles and secrets

| Identity | Credential source | Authorized operations |
|---|---|---|
| EB instance profile | EC2 IMDSv2 (temporary creds) | Presign `raw/*` upload (s3:PutObject), presign `processed/*` GET, read app secret, SSM |
| ECS task role (worker) | ECS task credentials | Get `raw/*`, put `processed/*`, SQS receive/delete, read app secret |
| ECS task **execution** role | ECS task execution agent | Pull image from ECR, write CloudWatch logs (no application DB access) |
| ECS **schema task** role | One-off ECS credentials | Read app secret **and** Aurora admin-managed secret |
| EC2 imported appliance profile | EC2 IMDSv2 if supported | SSM; migration-specific S3/DB grants should exist only for the cutover window |
| VM Import service `vmimport` | AWS service principal `vmie.amazonaws.com` | Read OVA import bucket and register AMI / snapshots |

**Additional access for historical backfill:** this repository's default legacy-VM profile is intentionally SSM-only. Before running `07-Backfill-Legacy.py` on imported EC2, temporarily grant S3 `PutObject` to `raw/*`, Secrets Manager GetSecretValue on app secret, inbound DB SG `3306` from legacy VM SG, and outbound HTTPS. Revoke all three when reconciled. This is *not* automatically granted to reduce risk.

## Naming and operational identifiers

Run `terraform -chdir=terraform output` for live names. Buckets contain `project_slug`, account ID and a random suffix for global uniqueness, with **no dots** (a Transfer Acceleration requirement). Secret passwords never appear in outputs. The actual password **is stored in local Terraform state** because Terraform manages an app Secrets Manager version; avoid committing state and use remote encrypted state for teamwork.

The examples use `ap-south-1` because S3 Transfer Acceleration support is documented for Mumbai. In other regions verify acceleration and Aurora instance availability before applying.
