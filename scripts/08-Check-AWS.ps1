$ErrorActionPreference = 'Stop'
$tf = Join-Path (Split-Path -Parent $PSScriptRoot) 'terraform'
$region = (terraform -chdir="$tf" output -raw region).Trim()
$url = (terraform -chdir="$tf" output -raw web_url).Trim()
$bucket = (terraform -chdir="$tf" output -raw assets_bucket).Trim()
$cluster = (terraform -chdir="$tf" output -raw ecs_cluster).Trim()
$service = (terraform -chdir="$tf" output -raw ecs_worker_service).Trim()
$queue = (terraform -chdir="$tf" output -raw sqs_queue_url).Trim()
Write-Host "Portal: $url" -ForegroundColor Cyan
foreach($route in @('/healthz','/readyz')) {
  try { $result=Invoke-RestMethod -Uri "$url$route" -TimeoutSec 15; Write-Host "$route => $($result.status)" }
  catch { Write-Warning "$route failed: $($_.Exception.Message)" }
}
aws s3api get-bucket-accelerate-configuration --bucket $bucket --region $region
aws s3api get-public-access-block --bucket $bucket --region $region
aws sqs get-queue-attributes --region $region --queue-url $queue --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
aws ecs describe-services --region $region --cluster $cluster --services $service `
  --query 'services[0].{desired:desiredCount,running:runningCount,deployments:deployments[0].rolloutState}'
Write-Host 'Inspect failed jobs in the SQS dead-letter queue and CloudWatch before cutover.'
