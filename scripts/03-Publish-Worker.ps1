param([Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9_.-]+$')][string]$Tag)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tf = Join-Path $root 'terraform'
Push-Location $root
try {
  $repo = (terraform -chdir="$tf" output -raw ecr_repository_url).Trim()
  $region = (terraform -chdir="$tf" output -raw region).Trim()
  if (-not $repo -or -not $region) { throw 'Terraform outputs missing; deploy infrastructure first' }
  $registry = $repo.Split('/')[0]
  Write-Host "Building worker for linux/amd64: $repo`:$Tag" -ForegroundColor Cyan
  aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry
  if ($LASTEXITCODE -ne 0) { throw 'Docker ECR authentication failed' }
  docker build --platform linux/amd64 -f worker/Dockerfile -t "${repo}:$Tag" .
  if ($LASTEXITCODE -ne 0) { throw 'Docker build failed' }
  docker push "${repo}:$Tag"
  if ($LASTEXITCODE -ne 0) { throw 'Docker push failed; ECR image tags are immutable: use a NEW tag' }
  Write-Host "Published ${repo}:$Tag" -ForegroundColor Green
  Write-Host "Next: update terraform.tfvars worker_image_tag = '$Tag', then run: terraform -chdir=terraform apply"
  Write-Host 'Leave worker_desired_count=0 until schema bootstrap succeeds.'
} finally { Pop-Location }
