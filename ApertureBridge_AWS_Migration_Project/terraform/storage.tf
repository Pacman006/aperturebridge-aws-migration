resource "aws_s3_bucket" "assets" {
  bucket = local.assets_name
  force_destroy = var.environment == "lab"
}
resource "aws_s3_bucket" "import" {
  bucket = local.import_name
  force_destroy = var.environment == "lab"
}
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_public_access_block" "import" {
  bucket = aws_s3_bucket.import.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "import" {
  bucket = aws_s3_bucket.import.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_versioning" "import" {
  bucket = aws_s3_bucket.import.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_accelerate_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  status = "Enabled"
}
resource "aws_s3_bucket_cors_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "POST"]
    allowed_origins = var.cors_allowed_origins
    max_age_seconds = 300
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    id = "abort-incomplete-multipart"
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
resource "aws_s3_bucket_policy" "assets_tls" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Sid = "DenyPlainHTTP", Effect = "Deny", Principal = "*", Action = "s3:*",
    Resource = [aws_s3_bucket.assets.arn, "${aws_s3_bucket.assets.arn}/*"],
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
  depends_on = [aws_s3_bucket_public_access_block.assets]
}
resource "aws_s3_bucket_policy" "import_tls" {
  bucket = aws_s3_bucket.import.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Sid = "DenyPlainHTTP", Effect = "Deny", Principal = "*", Action = "s3:*",
    Resource = [aws_s3_bucket.import.arn, "${aws_s3_bucket.import.arn}/*"],
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
  depends_on = [aws_s3_bucket_public_access_block.import]
}
