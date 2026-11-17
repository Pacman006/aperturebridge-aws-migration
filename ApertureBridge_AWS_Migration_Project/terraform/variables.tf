variable "aws_region" {
  description = "Use a region supporting Aurora and S3 Transfer Acceleration; ap-south-1 is verified."
  type = string
  default = "ap-south-1"
}
variable "project_slug" {
  description = "Lowercase DNS-safe prefix (no dots; acceleration forbids dots in bucket names)."
  type = string
  default = "aperturebridge"
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project_slug))
    error_message = "Use 3-16 lowercase letters, digits or hyphens; start with a letter."
  }
}
variable "environment" {
  type = string
  default = "lab"
}
variable "vpc_cidr" {
  type = string
  default = "10.32.0.0/16"
}
variable "db_name" {
  type = string
  default = "aperturebridge"
}
variable "db_instance_class" {
  type = string
  default = "db.t4g.medium"
}
variable "db_deletion_protection" {
  type = bool
  default = false
}
variable "db_final_snapshot" {
  type = bool
  default = false
}
variable "ha_nat" {
  type = bool
  default = false
}
variable "eb_min_instances" {
  type = number
  default = 1
}
variable "eb_max_instances" {
  type = number
  default = 2
}
variable "eb_instance_type" {
  type = string
  default = "t3.small"
}
variable "worker_desired_count" {
  description = "Leave at 0 until the worker image has been pushed to ECR."
  type = number
  default = 0
}
variable "worker_image_tag" {
  type = string
  default = "v1"
}
variable "eb_solution_stack_name" {
  description = "Check aws elasticbeanstalk list-available-solution-stacks; value is current on 2026-11-17."
  type = string
  default = "64bit Amazon Linux 2023 v4.14.3 running Python 3.12"
}
variable "cors_allowed_origins" {
  description = "Lab '*' only; set exact HTTPS site origin(s) before production."
  type = list(string)
  default = ["*"]
}
variable "acm_certificate_arn" {
  description = "ACM certificate in the SAME region, covering the chosen DNS name. Required for HTTPS mode."
  type = string
  default = ""
}
variable "lab_http_mode" {
  description = "Non-production ONLY: use insecure port 80 if no certificate/domain is available."
  type = bool
  default = true
}
