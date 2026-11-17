# Troubleshooting by symptom

| Symptom | Diagnostic command / check | Most likely correction |
|---|---|---|
| `git` command unavailable | `Get-Command git`; check `C:\Program Files\Git\cmd` | Install Git for Windows or update PATH; reopen PowerShell |
| `terraform` command unavailable | `Get-Command terraform` | Add Terraform binary directory to PATH; reopen PowerShell |
| Terraform plan wants wrong account/region | `aws sts get-caller-identity`; inspect provider + variables | Fix AWS SSO profile / selected region; never apply blind |
| `terraform init` cannot download provider | Verify internet/proxy access; `terraform providers` | Install via approved outbound network; retry init, not `apply` |
| Duplicate `vmimport` IAM role | `aws iam get-role --role-name vmimport` | Import existing role into Terraform or use approved preexisting role; don't delete organization-owned role |
| S3 acceleration rejected | `aws s3api get-bucket-accelerate-configuration` | Check bucket has no dots, chosen supported region, endpoint and permission |
| `AccessDenied` for presigned S3 POST | Browser devtools, S3 bucket policy, POST policy, ALB origin | Ensure EB IAM PutObject raw/*, exact domain/CORS, TLS and signature region |
| Upload is PENDING forever | SQS queue depth, ECS task status, worker CloudWatch logs | Start ECS desired 1, verify S3 notification and queue policy, DB schema, SQS creds |
| Worker repeatedly fails image | CloudWatch `/aperturebridge/.../worker`, SQS DLQ | Check S3 key, payload, size, unsupported image, DB auth / TLS, retry after repair |
| `Name or service not known` from ECS to Aurora | `terraform output aurora_writer_endpoint`, VPC DNS, SG | Check VPC DNS true, DB writer running, app/worker SG and port 3306 |
| `Access denied for user 'aperture_app'` | One-off ECS schema task exit/logs | Run schema initializer first; verify app secret, DB grants, credential rotation |
| RDS certificate verify failure | `DB_TLS_CA` path, official RDS global bundle, hostname | Repackage EB ZIP or rebuild worker after downloading current CA; don't disable SSL verification |
| ECR pull `CannotPullContainerError` | ECR repo URI/tag, ECS task execution role, subnet NAT | Publish immutable correct tag, apply updated task def and worker count, check outbound 443 |
| EB health red immediately after first apply | `/healthz`, EB events and deployment version | First deploy serves default sample version; publish actual web application next |
| EB `ModuleNotFoundError: shared` | Inspect application ZIP root listing | Source bundle must include `shared/` next to `application.py` |
| EB application version label already exists | `aws elasticbeanstalk describe-application-versions` | Publish a **new** version label; do not overwrite immutable release |
| Local upload appears stuck | `docker compose ... logs worker localstack mysql` | Check LocalStack ready hook, object-created S3 notification, queue URL, DB init |
| Docker `Cannot connect to daemon` | `docker info` | Start Docker Desktop and WSL 2 engine; restart after updates |
| OVA import fails | `aws ec2 describe-import-image-tasks --import-task-ids ...` | Confirm OS, boot mode, VM disks, image license, `vmimport` role and access |
| EC2 has public IP but Session Manager offline | SSM Agent installed? EC2 role, SG egress, VPC DNS | Install/start supported SSM Agent; ensure outbound 443/SSM and AWS supported VM image |
| DMS full load/CDC failure | DMS task log, binlog vars, endpoint tests | Confirm DB permissions, ROW binlog, SG routing, retention and schema compatibility |
| GitHub `Authentication failed` | `gh auth status`, `git remote -v` | Browser login via Git Credential Manager / gh; check repo write access/SSO |
| GitHub push rejected (remote ahead) | `git fetch origin`, `git log --all --oneline --graph` | Integrate remote commits intentionally; avoid force push |
| Terraform destroy fails after imported EC2 | Describe EC2 instance, service-managed resources, IAM roles | Manual VM / DMS cleanup before Terraform destroy; confirm snapshots/backups |

### Recovery posture

If an image event fails repeatedly, correct the root cause then redrive messages from DLQ to the source queue after validating deduplication and capacity. A corrupt image should be intentionally `REJECTED`; requeueing it is not useful. If Aurora is unreachable, don't acknowledge messages before successful status writes; visibility timeout and DLQ preserve events while an incident is investigated. Disable new uploads if queue retention/backlog threatens data integrity, and communicate the user-facing impact.
