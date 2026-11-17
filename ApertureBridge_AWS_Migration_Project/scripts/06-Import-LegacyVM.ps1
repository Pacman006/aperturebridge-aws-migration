param(
 [Parameter(Mandatory=$true)][string]$OvaPath,
 [ValidateSet('AWS','BYOL')][string]$LicenseType='AWS',
 [string]$InstanceType='t3.small'
)
$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $OvaPath -ErrorAction Stop).Path
if (-not $resolved.ToLower().EndsWith('.ova')) { throw 'Provide an actual, compatible OVA VM image' }
$tf = Join-Path (Split-Path -Parent $PSScriptRoot) 'terraform'
$bucket = (terraform -chdir="$tf" output -raw import_bucket).Trim()
$region = (terraform -chdir="$tf" output -raw region).Trim()
$public = (terraform -chdir="$tf" output -raw public_subnet).Trim()
$sg = (terraform -chdir="$tf" output -raw imported_vm_security_group).Trim()
$profile = (terraform -chdir="$tf" output -raw imported_vm_instance_profile).Trim()
$key = 'vm-images/' + [IO.Path]::GetFileName($resolved)
Write-Warning 'VM import and EC2 resources incur charges; verify OS licensing, drivers and VM Import/Export prerequisites.'
aws s3 cp "$resolved" "s3://$bucket/$key" --region $region
if ($LASTEXITCODE -ne 0) { throw 'OVA upload failed' }
$disk = ConvertTo-Json -InputObject @(@{ Format='OVA'; UserBucket=@{ S3Bucket=$bucket; S3Key=$key }}) -Depth 6
$tmp = [IO.Path]::GetTempFileName()
try {
  [IO.File]::WriteAllText($tmp, $disk, [System.Text.UTF8Encoding]::new($false))
  $task = aws ec2 import-image --region $region --description 'ApertureBridge migration validation VM' `
    --license-type $LicenseType --disk-containers "file://$tmp" --output json | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0) { throw 'EC2 import-image request failed' }
  $id = $task.ImportTaskId
  Write-Host "Import task: $id (may be lengthy for large VM disks)."
  do {
    Start-Sleep -Seconds 30
    $status = aws ec2 describe-import-image-tasks --region $region --import-task-ids $id --output json | ConvertFrom-Json
    $entry = $status.ImportImageTasks[0]
    Write-Host "$($entry.Status): $($entry.StatusMessage)"
    if ($entry.Status -in @('deleted','deleting')) { throw "Import failed: $($entry.StatusMessage)" }
  } while ($entry.Status -ne 'completed')
  if (-not $entry.ImageId) { throw 'Import finished without an AMI ID' }
  $instance = aws ec2 run-instances --region $region --image-id $entry.ImageId --instance-type $InstanceType `
    --subnet-id $public --security-group-ids $sg --associate-public-ip-address `
    --iam-instance-profile "Name=$profile" --count 1 --output json | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0) { throw 'VM imported as AMI, but EC2 launch failed. AMI remains available.' }
  $instanceId = $instance.Instances[0].InstanceId
  aws ec2 wait instance-running --region $region --instance-ids $instanceId
  $info = aws ec2 describe-instances --region $region --instance-ids $instanceId `
    --query 'Reservations[0].Instances[0].[InstanceId,PublicIpAddress,State.Name]' --output text
  Write-Host "Imported instance $instanceId details: $info" -ForegroundColor Green
  Write-Host 'Security group permits no inbound ports. Use AWS Systems Manager Session Manager after verifying agent.'
} finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
