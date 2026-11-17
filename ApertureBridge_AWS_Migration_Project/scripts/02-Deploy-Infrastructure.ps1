param([switch]$SkipPreflight)
$ErrorActionPreference = 'Stop'
if (-not $SkipPreflight) { & "$PSScriptRoot/00-Preflight.ps1" -Cloud }
$root = Split-Path -Parent $PSScriptRoot
$tf = Join-Path $root 'terraform'
if (-not (Test-Path "$tf/terraform.tfvars")) { throw 'Copy terraform.tfvars.example to terraform.tfvars, then review it' }
Write-Warning 'This provisions billable AWS services: Aurora, NAT, Elastic Beanstalk, S3, ECS, etc.'
terraform -chdir="$tf" init
if ($LASTEXITCODE -ne 0) { throw 'Terraform init failed' }
terraform -chdir="$tf" plan -out=aperturebridge.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Terraform plan failed' }
terraform -chdir="$tf" apply aperturebridge.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Terraform apply failed' }
terraform -chdir="$tf" output
