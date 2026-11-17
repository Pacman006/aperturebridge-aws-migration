resource "aws_ecr_repository" "worker" {
  name = "${local.prefix}-worker"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}
resource "aws_ecr_lifecycle_policy" "worker" {
  repository = aws_ecr_repository.worker.name
  policy = jsonencode({ rules = [{ rulePriority = 1, description = "Keep recent worker images",
    selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 15 },
    action = { type = "expire" } }] })
}
resource "aws_cloudwatch_log_group" "worker" {
  name = "/aperturebridge/${var.environment}/worker"
  retention_in_days = 14
}
resource "aws_ecs_cluster" "this" {
  name = "${local.prefix}-cluster"
  setting {
    name = "containerInsights"
    value = "enabled"
  }
}
locals {
  worker_env = [
    { name = "AWS_REGION", value = var.aws_region },
    { name = "APP_BUCKET", value = aws_s3_bucket.assets.id },
    { name = "DB_HOST", value = aws_rds_cluster.aurora.endpoint },
    { name = "DB_NAME", value = var.db_name },
    { name = "DB_SECRET_ARN", value = aws_secretsmanager_secret.app.arn },
    { name = "SQS_QUEUE_URL", value = aws_sqs_queue.assets.id },
    { name = "DB_TLS_CA", value = "/srv/shared/certs/global-bundle.pem" },
    { name = "PYTHONDONTWRITEBYTECODE", value = "1" }
  ]
  worker_image = "${aws_ecr_repository.worker.repository_url}:${var.worker_image_tag}"
  log_configuration = { logDriver = "awslogs", options = {
    awslogs-group = aws_cloudwatch_log_group.worker.name,
    awslogs-region = var.aws_region,
    awslogs-stream-prefix = "fargate"
  } }
}
resource "aws_ecs_task_definition" "worker" {
  family = "${local.prefix}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"
  cpu = "512"
  memory = "1024"
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture = "X86_64"
  }
  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn = aws_iam_role.worker.arn
  container_definitions = jsonencode([{ name = "worker", image = local.worker_image,
    essential = true, readonlyRootFilesystem = true,
    environment = local.worker_env, logConfiguration = local.log_configuration }])
}
resource "aws_ecs_task_definition" "schema" {
  family = "${local.prefix}-schema"
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"
  cpu = "512"
  memory = "1024"
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture = "X86_64"
  }
  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn = aws_iam_role.schema.arn
  container_definitions = jsonencode([{ name = "worker", image = local.worker_image,
    command = ["python", "-m", "worker.schema"], essential = true, readonlyRootFilesystem = true,
    environment = concat(local.worker_env, [{ name = "DB_ADMIN_SECRET_ARN", value = aws_rds_cluster.aurora.master_user_secret[0].secret_arn }]),
    logConfiguration = local.log_configuration }])
}
resource "aws_ecs_service" "worker" {
  name = "${local.prefix}-worker"
  cluster = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count = var.worker_desired_count
  launch_type = "FARGATE"
  enable_execute_command = false
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent = 200
  network_configuration {
    subnets = aws_subnet.app[*].id
    security_groups = [aws_security_group.worker.id]
    assign_public_ip = false
  }
  depends_on = [aws_iam_role_policy.worker, aws_iam_role_policy_attachment.ecs_execution]
}
