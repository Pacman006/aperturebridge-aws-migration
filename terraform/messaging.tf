resource "aws_sqs_queue" "dead_letter" {
  name = "${local.prefix}-asset-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled = true
}
resource "aws_sqs_queue" "assets" {
  name = "${local.prefix}-asset-created"
  visibility_timeout_seconds = 180
  message_retention_seconds = 345600
  sqs_managed_sse_enabled = true
  redrive_policy = jsonencode({ deadLetterTargetArn = aws_sqs_queue.dead_letter.arn, maxReceiveCount = 5 })
}
resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.assets.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Sid = "AllowS3ObjectCreated", Effect = "Allow",
    Principal = { Service = "s3.amazonaws.com" }, Action = "sqs:SendMessage",
    Resource = aws_sqs_queue.assets.arn,
    Condition = { ArnEquals = { "aws:SourceArn" = aws_s3_bucket.assets.arn },
                  StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
  }] })
}
resource "aws_s3_bucket_notification" "assets" {
  bucket = aws_s3_bucket.assets.id
  queue {
    queue_arn = aws_sqs_queue.assets.arn
    events = ["s3:ObjectCreated:*"]
    filter_prefix = "raw/"
  }
  depends_on = [aws_sqs_queue_policy.allow_s3]
}
