terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
  # Local state is for an isolated lab only. Configure an encrypted, locked
  # remote backend before collaborating or deploying real data.
}
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = "ApertureBridge", ManagedBy = "Terraform", Environment = var.environment }
  }
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}
resource "random_id" "suffix" {
  byte_length = 3
}
resource "random_password" "app" {
  length = 32
  special = true
  override_special = "!#%-_"
}
locals {
  prefix       = "${var.project_slug}-${var.environment}"
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
  assets_name  = "${var.project_slug}-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}-assets"
  import_name  = "${var.project_slug}-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}-import"
  common_tags  = { Workload = "ImageHostingMigration" }
}
