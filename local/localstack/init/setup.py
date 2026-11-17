"""LocalStack READY hook: no dependency on an AWS CLI binary in the container."""
import boto3
import json

REGION = "ap-south-1"
BUCKET = "aperturebridge-local-assets"
QUEUE = "aperturebridge-local-assets"
base = {"endpoint_url": "http://localhost:4566", "region_name": REGION,
        "aws_access_key_id": "test", "aws_secret_access_key": "test"}
s3 = boto3.client("s3", **base)
sqs = boto3.client("sqs", **base)
s3.create_bucket(Bucket=BUCKET, CreateBucketConfiguration={"LocationConstraint": REGION})
queue_url = sqs.create_queue(QueueName=QUEUE)["QueueUrl"]
queue_arn = sqs.get_queue_attributes(QueueUrl=queue_url,
                                     AttributeNames=["QueueArn"])["Attributes"]["QueueArn"]
policy = {"Version": "2012-10-17", "Statement": [{
    "Effect": "Allow", "Principal": {"Service": "s3.amazonaws.com"},
    "Action": "sqs:SendMessage", "Resource": queue_arn,
    "Condition": {"ArnEquals": {"aws:SourceArn": f"arn:aws:s3:::{BUCKET}"}}
}]}
sqs.set_queue_attributes(QueueUrl=queue_url, Attributes={"Policy": json.dumps(policy)})
s3.put_bucket_notification_configuration(
    Bucket=BUCKET,
    NotificationConfiguration={"QueueConfigurations": [{
        "QueueArn": queue_arn,
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {"Key": {"FilterRules": [{"Name": "prefix", "Value": "raw/"}]}}
    }]},
)
print(f"ApertureBridge local resources ready: {BUCKET}, {queue_url}")
