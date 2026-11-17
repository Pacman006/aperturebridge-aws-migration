data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
data "aws_iam_policy_document" "task_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "eb_instance" {
  name = "${local.prefix}-eb-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}
resource "aws_iam_instance_profile" "eb" {
  name = "${local.prefix}-eb-profile"
  role = aws_iam_role.eb_instance.name
}
resource "aws_iam_role_policy_attachment" "eb_managed" {
  role = aws_iam_role.eb_instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSElasticBeanstalkWebTier"
}
resource "aws_iam_role_policy_attachment" "eb_ssm" {
  role = aws_iam_role.eb_instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "eb_app" {
  name = "${local.prefix}-eb-app"
  role = aws_iam_role.eb_instance.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["${aws_s3_bucket.assets.arn}/raw/*"] },
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${aws_s3_bucket.assets.arn}/processed/*"] },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [aws_secretsmanager_secret.app.arn] }
  ] })
}
resource "aws_iam_role" "eb_service" {
  name = "${local.prefix}-eb-service"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "elasticbeanstalk.amazonaws.com" }, Action = "sts:AssumeRole"
  }] })
}
resource "aws_iam_role_policy_attachment" "eb_health" {
  role = aws_iam_role.eb_service.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}
resource "aws_iam_role_policy_attachment" "eb_updates" {
  role = aws_iam_role.eb_service.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}
resource "aws_iam_role" "ecs_execution" {
  name = "${local.prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.task_trust.json
}
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role = aws_iam_role.ecs_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role" "worker" {
  name = "${local.prefix}-ecs-worker"
  assume_role_policy = data.aws_iam_policy_document.task_trust.json
}
resource "aws_iam_role_policy" "worker" {
  role = aws_iam_role.worker.id
  name = "${local.prefix}-worker"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.assets.arn },
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${aws_s3_bucket.assets.arn}/raw/*"] },
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["${aws_s3_bucket.assets.arn}/processed/*"] },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [aws_secretsmanager_secret.app.arn] }
  ] })
}
resource "aws_iam_role" "schema" {
  name = "${local.prefix}-ecs-schema"
  assume_role_policy = data.aws_iam_policy_document.task_trust.json
}
resource "aws_iam_role_policy" "schema" {
  name = "${local.prefix}-schema"
  role = aws_iam_role.schema.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"],
      Resource = [aws_secretsmanager_secret.app.arn, aws_rds_cluster.aurora.master_user_secret[0].secret_arn] }
  ] })
}
resource "aws_iam_role" "vm" {
  name = "${local.prefix}-vm-ssm"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}
resource "aws_iam_role_policy_attachment" "vm_ssm" {
  role = aws_iam_role.vm.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "vm" {
  name = "${local.prefix}-vm-profile"
  role = aws_iam_role.vm.name
}
resource "aws_iam_role" "vm_import" {
  name = "vmimport"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "vmie.amazonaws.com" }, Action = "sts:AssumeRole",
    Condition = { StringEquals = { "sts:Externalid" = "vmimport" } }
  }] })
}
resource "aws_iam_role_policy" "vm_import" {
  name = "vmimport"
  role = aws_iam_role.vm_import.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket"],
      Resource = [aws_s3_bucket.import.arn, "${aws_s3_bucket.import.arn}/*"] },
    { Effect = "Allow", Action = ["ec2:ModifySnapshotAttribute", "ec2:CopySnapshot", "ec2:RegisterImage", "ec2:Describe*"], Resource = "*" }
  ] })
}
