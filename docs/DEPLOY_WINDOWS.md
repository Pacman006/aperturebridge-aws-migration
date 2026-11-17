# AWS lab deployment — Windows 10/11 PowerShell, exact sequence

**Goal:** provision cloud foundation, initialize Aurora app identity, publish ECS and EB, confirm one image reaches `READY`. This runbook assumes an authorized AWS learning account and a verified S3 Transfer Acceleration-supported region. It does **not** migrate actual ABC data without an OVA, database inventory and image manifest.

## A. Prepare your machine

1. Install Git for Windows, Docker Desktop with WSL 2 backend, Python 3.12 or 3.13, AWS CLI v2, and Terraform. Your existing Terraform 1.17.1 is above the project's `>=1.6` requirement; there is no need to update for this blueprint. Make sure Git/Docker are on the PATH. Close/reopen PowerShell after installation.
2. In PowerShell run `git --version`, `docker --version`, `python --version`, `aws --version`, `terraform version` and `docker info`. The last command must contact a running Docker engine.
3. Use `aws configure sso` and then `aws sso login --profile YOUR_PROFILE` if configured for IAM Identity Center. In the session set `$env:AWS_PROFILE='YOUR_PROFILE'`. Alternatively use an approved role. **Never use root access keys or paste credentials into scripts.**
4. Confirm identity: `aws sts get-caller-identity`. Confirm your selected region: `$env:AWS_DEFAULT_REGION='ap-south-1'`. Ensure you have IAM, VPC, RDS, ECS, ECR, S3, SQS, EB, SSM and CloudWatch permissions (or obtain deployment approval); AWS organizations may restrict these APIs.
5. Enable MFA, an AWS Budget alert and cost anomaly detection. Obtain service-quota permission for VPC NAT, elastic IPs, RDS DB class, EB EC2, Fargate and IPv4 addresses. Remember NAT, Aurora and the ALB keep billing even when no one uploads an image.
6. Extract the ZIP to a simple directory such as `C:\Projects\ApertureBridge_AWS_Migration_Project`; **quote paths containing spaces** with `Set-Location -LiteralPath`.

## B. Inspect and validate locally

```powershell
Set-Location -LiteralPath 'C:\Projects\ApertureBridge_AWS_Migration_Project'
Copy-Item terraform\terraform.tfvars.example terraform\terraform.tfvars
notepad terraform\terraform.tfvars
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r frontend\requirements.txt -r worker\requirements.txt -r requirements-dev.txt
terraform fmt -recursive terraform
pytest -q tests
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

Run `docker compose -f local/docker-compose.yml up --build -d` and upload a small test image to http://localhost:8080. Confirm `READY`; then `docker compose ... down`. **Do not proceed to AWS if local tests fail.**

## C. Provision cloud foundation

```powershell
aws sts get-caller-identity
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=review.tfplan
terraform -chdir=terraform apply review.tfplan
terraform -chdir=terraform output
```

Review resources/cost in the plan. If you select an unsupported instance class, EB platform, region or have insufficient quotas, stop and change the relevant variable: do **not** make undocumented console changes that cause Terraform drift. The first plan creates an ECR repository and ECS service with **desired count = 0**, thus no missing image pull. The initial EB environment may temporarily be unhealthy because it shows its default sample site and the configured `/healthz` endpoint is not yet deployed.

## D. Build backend and initialize database (mandatory ordering)

```powershell
.\scripts\03-Publish-Worker.ps1 -Tag v1
# Open terraform\terraform.tfvars and set worker_image_tag = "v1".
terraform -chdir=terraform apply
.\scripts\04-Initialize-Database.ps1
```

**Check schema task exit code = 0**. On failure, open CloudWatch Logs group `/aperturebridge/lab/worker` and troubleshoot Secrets Manager, DB connectivity, RDS CA validation or Aurora auth. Do not start regular worker until the bootstrap task exits successfully. In `terraform.tfvars`, set `worker_desired_count = 1`; run `terraform -chdir=terraform apply` and ensure ECS desired/running counts are both `1`.

## E. Publish website

```powershell
.\scripts\05-Publish-Frontend.ps1 -Version web-v1
terraform -chdir=terraform output -raw web_url
aws elasticbeanstalk describe-environments --application-name aperturebridge-lab-web `
  --environment-names aperturebridge-lab-web --query 'Environments[0].[Status,Health,VersionLabel,CNAME]' --output table
```

The publisher stages the files in a temporary folder, downloads the current official RDS trust bundle, creates a Beanstalk source ZIP with **`application.py`, `requirements.txt`, `Procfile`, templates, static and `shared/` at archive root**, registers a version in S3 and updates EB. Never commit or paste production database credentials into the ZIP.

Check `/healthz` (process) and `/readyz` (actual DB connection), then upload a test image and confirm it becomes `READY`. Run `.\scripts\08-Check-AWS.ps1`, review SQS DLQ depth and CloudWatch logs. Retest with a corrupt `.png` file and verify it is rejected rather than crashing worker. Production TLS cannot be tested until you have a valid ACM certificate and matching custom hostname.

## F. Production-mode hardening gate

The **default** `lab_http_mode=true` is intentionally nonproduction. Do not send real personal or business images. Before any real users:

1. Acquire a domain and validate an ACM certificate in the **same AWS region**. Create an alias/CNAME from the domain to the EB-managed ALB/CNAME. Confirm DNS resolution.
2. Change Terraform to `lab_http_mode=false`, set `acm_certificate_arn`, replace wildcard `cors_allowed_origins` with `https://YOUR_DOMAIN`, and set `eb_min_instances = 2`, `ha_nat = true`, `db_deletion_protection = true`, `db_final_snapshot = true`; apply carefully.
3. Add an HTTPS redirect (or disable port 80 as this blueprint does), plus Cognito/OIDC, tenancy enforcement, WAF, quotas, malware scanning, backup restore tests, private endpoint review, S3 lifecycle and alarms. Do not treat the lab as already conforming to a particular regulation.
4. Re-run user journey, failover, recovery and security tests. Confirm clean Terraform plan and an approved cutover/rollback plan before redirecting customer traffic.

## G. Clean up the lab and stop ongoing costs

```powershell
# Imported EC2 instances and manually configured DMS replication are NOT
# covered by Terraform and must be terminated manually first.
.\scripts\09-Destroy-Lab.ps1 -Destroy
```

**Destructive:** the lab's S3 buckets have `force_destroy=true`; `db_final_snapshot=false` by default; destroying the lab can delete all stored images and the Aurora database without a final snapshot. Export anything you need first. Secrets Manager deletion rules differ between lab and production. Verify no NAT Gateway, load balancer, EIP, ECS service, RDS instance, DMS task or imported VM remains in the AWS console afterward.
