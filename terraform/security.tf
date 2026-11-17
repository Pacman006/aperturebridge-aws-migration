resource "aws_security_group" "alb" {
  name_prefix = "${local.prefix}-alb-"
  description = "Public application load balancer"
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.prefix}-alb" }
}
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  count = var.lab_http_mode ? 1 : 0
  security_group_id = aws_security_group.alb.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 80
  to_port = 80
  ip_protocol = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = var.lab_http_mode ? 0 : 1
  security_group_id = aws_security_group.alb.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 443
  to_port = 443
  ip_protocol = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.web.id
  from_port = 80
  to_port = 80
  ip_protocol = "tcp"
}
resource "aws_security_group" "web" {
  name_prefix = "${local.prefix}-web-"
  vpc_id = aws_vpc.main.id
  description = "Private Beanstalk instances"
}
resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id = aws_security_group.web.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port = 80
  to_port = 80
  ip_protocol = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "web_out" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol = "-1"
}
resource "aws_security_group" "worker" {
  name_prefix = "${local.prefix}-worker-"
  description = "Fargate tasks; outbound only"
  vpc_id = aws_vpc.main.id
}
resource "aws_vpc_security_group_egress_rule" "worker_out" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol = "-1"
}
resource "aws_security_group" "db" {
  name_prefix = "${local.prefix}-db-"
  description = "Aurora MySQL only from application and worker"
  vpc_id = aws_vpc.main.id
}
resource "aws_vpc_security_group_ingress_rule" "db_from_web" {
  security_group_id = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.web.id
  from_port = 3306
  to_port = 3306
  ip_protocol = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "db_from_worker" {
  security_group_id = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.worker.id
  from_port = 3306
  to_port = 3306
  ip_protocol = "tcp"
}
resource "aws_security_group" "imported_vm" {
  name_prefix = "${local.prefix}-legacy-"
  vpc_id = aws_vpc.main.id
  description = "Public IP for migration validation; no inbound ports. Use SSM."
}
resource "aws_vpc_security_group_egress_rule" "legacy_out" {
  security_group_id = aws_security_group.imported_vm.id
  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol = "-1"
}
