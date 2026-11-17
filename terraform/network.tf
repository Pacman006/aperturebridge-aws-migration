resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = { Name = "${local.prefix}-vpc" }
}
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.main.id
}
resource "aws_subnet" "public" {
  count = 2
  vpc_id = aws_vpc.main.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = local.azs[count.index]
  map_public_ip_on_launch = false
  tags = { Name = "${local.prefix}-public-${count.index+1}", Tier = "public" }
}
resource "aws_subnet" "app" {
  count = 2
  vpc_id = aws_vpc.main.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index+10)
  availability_zone = local.azs[count.index]
  tags = { Name = "${local.prefix}-app-${count.index+1}", Tier = "private-app" }
}
resource "aws_subnet" "db" {
  count = 2
  vpc_id = aws_vpc.main.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index+20)
  availability_zone = local.azs[count.index]
  tags = { Name = "${local.prefix}-db-${count.index+1}", Tier = "isolated-db" }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}
resource "aws_route" "public_internet" {
  route_table_id = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.this.id
}
resource "aws_route_table_association" "public" {
  count = 2
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_eip" "nat" {
  count = var.ha_nat ? 2 : 1
  domain = "vpc"
  depends_on = [aws_internet_gateway.this]
}
resource "aws_nat_gateway" "this" {
  count = var.ha_nat ? 2 : 1
  allocation_id = aws_eip.nat[count.index].id
  subnet_id = aws_subnet.public[count.index].id
  depends_on = [aws_route.public_internet]
}
resource "aws_route_table" "app" {
  count = 2
  vpc_id = aws_vpc.main.id
}
resource "aws_route" "app_outbound" {
  count = 2
  route_table_id = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.this[var.ha_nat ? count.index : 0].id
}
resource "aws_route_table_association" "app" {
  count = 2
  subnet_id = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id
}
resource "aws_route_table_association" "db" {
  count = 2
  subnet_id = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}
resource "aws_vpc_endpoint" "s3" {
  vpc_id = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [for route in aws_route_table.app : route.id]
  tags = { Name = "${local.prefix}-s3-gateway" }
}
