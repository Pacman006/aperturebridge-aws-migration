resource "aws_db_subnet_group" "this" {
  name = "${local.prefix}-db-subnets"
  subnet_ids = aws_subnet.db[*].id
}
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${local.prefix}-aurora"
  engine = "aurora-mysql"
  database_name = var.db_name
  master_username = "platformadmin"
  manage_master_user_password = true
  storage_encrypted = true
  db_subnet_group_name = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  backup_retention_period = 7
  preferred_backup_window = "19:00-20:00"
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = !var.db_final_snapshot
  final_snapshot_identifier = var.db_final_snapshot ? "${local.prefix}-final" : null
  apply_immediately = var.environment == "lab"
  copy_tags_to_snapshot = true
}
resource "aws_rds_cluster_instance" "writer" {
  identifier = "${local.prefix}-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class = var.db_instance_class
  engine = aws_rds_cluster.aurora.engine
  publicly_accessible = false
  db_subnet_group_name = aws_db_subnet_group.this.name
  auto_minor_version_upgrade = true
}
resource "aws_secretsmanager_secret" "app" {
  name = "${local.prefix}/database/app"
  recovery_window_in_days = var.environment == "lab" ? 0 : 30
  description = "Non-administrative application account, created by schema bootstrap."
}
resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({ username = "aperture_app", password = random_password.app.result })
}
