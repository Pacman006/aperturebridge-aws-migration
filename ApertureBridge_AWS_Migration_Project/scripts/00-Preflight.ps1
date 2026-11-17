param([switch]$Cloud)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Write-Host "ApertureBridge preflight" -ForegroundColor Cyan
foreach ($tool in @('git','python','docker','terraform')) {
  if (Get-Command $tool -ErrorAction SilentlyContinue) { & $tool --version 2>&1 | Select-Object -First 2 }
  else { Write-Warning "$tool is missing from PATH"; if ($tool -in @('git','python','terraform')) { throw "Missing required tool: $tool" } }
}
if ($Cloud) {
  if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI v2 is not installed' }
  aws --version
  $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0 -or -not $identity.Account) { throw 'AWS login failed: use aws configure sso / aws sso login' }
  Write-Host "AWS identity confirmed for account $($identity.Account)" -ForegroundColor Green
}
Write-Host 'Preflight finished. Make sure the selected AWS account is a LAB account.' -ForegroundColor Green
