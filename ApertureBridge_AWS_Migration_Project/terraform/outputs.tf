output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}
output "region" {
  value = var.aws_region
}
output "web_url" {
  value = "${var.lab_http_mode ? "http" : "https"}://${aws_elastic_beanstalk_environment.web.cname}"
}
output "eb_application" {
  value = aws_elastic_beanstalk_application.web.name
}
output "eb_environment" {
  value = aws_elastic_beanstalk_environment.web.name
}
output "assets_bucket" {
  value = aws_s3_bucket.assets.id
}
output "import_bucket" {
  value = aws_s3_bucket.import.id
}
output "accelerate_endpoint" {
  value = "${aws_s3_bucket.assets.id}.s3-accelerate.amazonaws.com"
}
output "aurora_writer_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
}
output "app_secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}
output "ecs_cluster" {
  value = aws_ecs_cluster.this.name
}
output "ecs_worker_service" {
  value = aws_ecs_service.worker.name
}
output "ecs_worker_task_definition" {
  value = aws_ecs_task_definition.worker.arn
}
output "ecs_schema_task_definition" {
  value = aws_ecs_task_definition.schema.arn
}
output "ecr_repository_url" {
  value = aws_ecr_repository.worker.repository_url
}
output "sqs_queue_url" {
  value = aws_sqs_queue.assets.id
}
output "sqs_dlq_url" {
  value = aws_sqs_queue.dead_letter.id
}
output "private_app_subnets" {
  value = aws_subnet.app[*].id
}
output "public_subnet" {
  value = aws_subnet.public[0].id
}
output "worker_security_group" {
  value = aws_security_group.worker.id
}
output "imported_vm_security_group" {
  value = aws_security_group.imported_vm.id
}
output "imported_vm_instance_profile" {
  value = aws_iam_instance_profile.vm.name
}
