$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  python -m compileall -q frontend worker shared scripts tests
  if ($LASTEXITCODE -ne 0) { throw 'Python compile failed' }
  python -m pytest -q tests
  if ($LASTEXITCODE -ne 0) { throw 'Python tests failed' }
  terraform fmt -recursive terraform
  if ($LASTEXITCODE -ne 0) { throw 'Terraform formatter failed; inspect .tf syntax' }
  terraform -chdir=terraform init -backend=false -input=false
  if ($LASTEXITCODE -ne 0) { throw 'Terraform init failed; check network/provider downloads' }
  terraform -chdir=terraform validate
  if ($LASTEXITCODE -ne 0) { throw 'Terraform validation failed' }
  Write-Host 'All locally available tests passed.' -ForegroundColor Green
} finally { Pop-Location }
