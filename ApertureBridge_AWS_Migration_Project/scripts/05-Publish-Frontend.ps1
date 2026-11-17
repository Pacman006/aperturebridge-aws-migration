param([Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9_.-]+$')][string]$Version)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tf = Join-Path $root 'terraform'
$region = (terraform -chdir="$tf" output -raw region).Trim()
$importBucket = (terraform -chdir="$tf" output -raw import_bucket).Trim()
$app = (terraform -chdir="$tf" output -raw eb_application).Trim()
$env = (terraform -chdir="$tf" output -raw eb_environment).Trim()
$stage = Join-Path ([IO.Path]::GetTempPath()) ('aperturebridge-eb-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $stage | Out-Null
try {
  Copy-Item (Join-Path $root 'frontend/*') $stage -Recurse -Force
  Copy-Item (Join-Path $root 'shared') (Join-Path $stage 'shared') -Recurse -Force
  # Keep release archives clean even if Python was compiled locally.
  Get-ChildItem -LiteralPath $stage -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
  Get-ChildItem -LiteralPath $stage -Recurse -File -Filter '*.pyc' | Remove-Item -Force
  New-Item -ItemType Directory -Force (Join-Path $stage 'shared/certs') | Out-Null
  Invoke-WebRequest 'https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem' `
    -OutFile (Join-Path $stage 'shared/certs/global-bundle.pem')
  if ((Get-Item (Join-Path $stage 'shared/certs/global-bundle.pem')).Length -lt 1024) { throw 'RDS TLS certificate bundle download looks incomplete' }
  $zip = Join-Path ([IO.Path]::GetTempPath()) ("aperturebridge-$Version.zip")
  if (Test-Path $zip) { Remove-Item $zip }
  Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
  $key = "elasticbeanstalk/$Version.zip"
  aws s3 cp $zip "s3://$importBucket/$key" --region $region
  if ($LASTEXITCODE -ne 0) { throw 'Could not upload Beanstalk source bundle to S3' }
  aws elasticbeanstalk create-application-version --region $region --application-name $app `
    --version-label $Version --source-bundle "S3Bucket=$importBucket,S3Key=$key" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Failed to register application version. Choose a new version label.' }
  aws elasticbeanstalk update-environment --region $region --environment-name $env --version-label $Version | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Beanstalk update failed. Inspect environment events.' }
  Write-Host "Version $Version submitted to $env. Check EB Environment Health = Green, then /healthz and /readyz." -ForegroundColor Green
} finally { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
