# AWS documentation and standards references

URLs below point to the vendor's technical documentation, reviewed for this blueprint on **17 November 2026**. Verify again before a real deployment because service support, pricing, IAM requirements and platform versions change.

- [Elastic Beanstalk supported platforms](https://docs.aws.amazon.com/elasticbeanstalk/latest/platforms/platforms-supported.html) — Python 3.12 on Amazon Linux 2023 is supported in the current platform list.
- [Deploy a Flask application to Elastic Beanstalk](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/create-deploy-python-flask.html) — `application.py`, requirements, EB deployment practices.
- [Application Load Balancer HTTPS listener](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environments-cfg-alb.html) — HTTPS listener, ACM certificate, default process.
- [HTTP to HTTPS redirection options](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/configuring-https-httpredirect.html) — configure redirect for production domains.
- [S3 Transfer Acceleration limitations and supported regions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/transfer-acceleration.html) — only supported regions; bucket name must have no dots.
- [S3 accelerated endpoints](https://docs.aws.amazon.com/AmazonS3/latest/userguide/transfer-acceleration-getting-started.html) — `bucket.s3-accelerate.amazonaws.com` endpoint semantics.
- [S3 notification event destinations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/notification-how-to-event-types-and-destinations.html) — SQS **Standard**, same-region requirement, resource policy, duplicate notifications.
- [ECS Task Execution IAM role](https://docs.aws.amazon.com/ecs/latest/developerguide/task_execution_IAM_role.html) — distinguishes pull/log role from the workload task role.
- [VM Import/Export required IAM permissions](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html) — special `vmimport` role and `iam:PassRole`.
- [Import OVA virtual machine image](https://docs.aws.amazon.com/vm-import/latest/userguide/import-vm-image.html) — `ec2 import-image` and prerequisites.
- [MySQL source requirements for DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.MySQL.html) — binlog, CDC, grants, MySQL compatibility and migration limitations.
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html) — reliability, security, sustainability, performance, operational excellence and cost.
- [AWS Pricing Calculator](https://calculator.aws/) — estimate current costs, not a fixed lab monthly claim.
- [GitHub Docs: add locally hosted code](https://docs.github.com/en/repositories/creating-and-managing-repositories/adding-locally-hosted-code-to-github) — create/push local repository.
- [GitHub CLI authentication](https://cli.github.com/manual/gh_auth_login) — interactive browser auth.

The training PDF used as requirements source is titled **AWS Migration certification project.pdf**, contains two pages, and carries a 2018 training-company attribution. This repository paraphrases requirements instead of bundling the copyrighted source PDF.
