# Security, reliability and cost review

## Risk register and fixes

| Original/target risk | Mitigation built into the repository | Remaining production responsibility |
|---|---|---|
| Web, DB and processing share a single host | Independent EB/ECS/Aurora/S3 tiers; isolated DB subnets | Aurora replica for resilience, tested DR |
| Image uploads saturate EC2 bandwidth | S3 direct browser-to-bucket presigned POST | Auth, quotas, WAF and multi-part uploads for large objects |
| Untrusted images crash processor | Pillow verify + 10 MiB/20MP bounds, queue retries, DLQ | Malware scanning, stronger sandbox, MIME allowlist policy |
| Processing is synchronous / untracked | SQS async worker; MySQL status; deterministic keys | Backpressure autoscaling and DLQ alarms |
| Credentials hardcoded in scripts | AWS SDK instance/task roles and Secrets Manager | Rotate DB app secret, secure Terraform state, private endpoints |
| Public database / excessive open ports | Isolated DB routes and SG-to-SG 3306; worker no ingress | SG least-priv egress refinements, audit and network access logs |
| Imported legacy appliance exposes SSH | Public IP but no incoming SG ports; SSM for management | OS/agent compatibility, patch baseline, time-box VM lifetime |
| S3 files publicly readable | Block Public Access, SSE-S3, TLS-only bucket policy | Object-level access audit, KMS if required, retention/PII controls |
| OVA has unexpected OS/driver setup | Check compatibility, import task status, test clone | Actual image required, licensing/boot and vulnerability assessment |
| DMS schema and binlog incompatibilities | Source prechecks and controlled migration gates | DBA-led DMS rehearsal, reconciliation, rollback |
| Secrets included in Terraform plan/state | Ignore tfstate from Git, no secret outputs | Encrypted locked remote state and access review before real data |
| Single NAT / one EB instance lab | Multi-subnet VPC and configurable HA variables | Set `ha_nat=true`, `eb_min_instances=2`, Aurora replica, run AZ fault tests |
| Public demo HTTP with unauthenticated uploads | Clearly labeled `lab_http_mode`; no real data | HTTPS/ACM + identity provider and abuse protections before production |

## Cost considerations

**Cost is NOT zero even with no uploads.** The largest steady charges are often Aurora instance and storage, NAT Gateway hourly + bytes, EB EC2 instance(s), public ALB, and Fargate task CPU/RAM. Additional charges may include EIP/public IPv4, log storage, S3 objects and versions, data transfer, DMS/VM import and Transfer Acceleration premium. Price varies by region, instance class, Free Tier/account credits, transfer location and actual usage. Rather than invent a monthly price, use the official [AWS Pricing Calculator](https://calculator.aws/) with real target-region values.

| Mode | Defaults | Suitable for |
|---|---|---|
| Local emulator | Docker Compose, no AWS bill (local CPU/storage) | Functional demo, first development |
| AWS **lab** | 1 NAT, 1 EB instance, 1 Aurora writer, ECS desired 0 until image/schema published | Short controlled testing only; still billable |
| AWS **production candidate** | 2 NAT, >=2 EB instances, Aurora writer + reader, TLS/custom domain, alarms, remote state | Requires security/DR approval; not enabled automatically |

The variable `db_instance_class = "db.t4g.medium"` and default EB platform are examples, not universal: verify `describe-orderable-db-instance-options` and `list-available-solution-stacks` in your selected region before applying. For production, avoid setting an RDS instance class only by expected price; measure traffic, memory, connections and failover RTO.

## Security before public exposure

1. Use ACM certificate and domain, force 443 and send HSTS where appropriate. Set explicit HTTPS S3 CORS origins instead of `*`.
2. Add Cognito/OIDC and tenant ownership checks to both intent creation and asset listing. At present anyone who reaches the demo can view all asset metadata; **this is not acceptable for real multitenant data**.
3. Protect API with AWS WAF rate limiting and per-user storage/billing quotas; cap pending uploads and reject malicious file formats. Set S3 quarantine policy, antivirus scanning and media content moderation if required.
4. Add account-wide CloudTrail, VPC Flow Logs, S3 access logging / CloudTrail data events as governed by privacy policy, GuardDuty, Config and patch management.
5. Use dedicated KMS keys only when compliance requires customer-managed cryptography; KMS policy design and request costs matter.
6. Store Terraform state in a dedicated encrypted S3 backend with state locking and tightly scoped IAM; local tfstate has SQL app password. Do not paste secrets into command-line flags recorded in shell history.
7. Set DB password rotation with application-aware, dual-user rotation and controlled deployment; Secrets Manager reading on process init means an uncontrolled rotation could break running connections.
8. Monitor SQS DLQ, max message age, ECS stopped tasks, EB ALB 5xx/health, Aurora CPU/memory/connections and storage, NAT throughput and access errors.
9. Establish retention/deletion and image classification policies. Versioning helps with accidental overwrites but may substantially increase storage bill; lifecycle/delete policies must follow data governance.
10. Test restore and failover with non-sensitive sample data, then record an achievable RPO/RTO rather than promising zero downtime.

## Model boundaries

The code and diagrams are custom for this case and contain no telemetry hooks or embedded tracking code. That does not guarantee that document authorship or code provenance cannot be inferred. Keep the project description accurate: this is an implemented reference plus a reproducible test and deployment procedure, **not evidence of a migration that already happened**.
