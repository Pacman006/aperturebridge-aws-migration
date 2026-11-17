param([switch]$Destroy)
$ErrorActionPreference = 'Stop'
$tf = Join-Path (Split-Path -Parent $PSScriptRoot) 'terraform'
if (-not $Destroy) { throw 'Destructive operation. Explicitly pass -Destroy and ensure backups were exported.' }
Write-Warning 'This will delete AWS compute, database, S3 buckets, and potentially ALL lab data (force_destroy=true).'
terraform -chdir="$tf" plan -destroy -out=destroy.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Plan failed' }
terraform -chdir="$tf" apply destroy.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Destroy failed; clean up imported EC2 / DMS resources separately' }
