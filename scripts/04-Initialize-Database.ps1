$ErrorActionPreference = 'Stop'
$tf = Join-Path (Split-Path -Parent $PSScriptRoot) 'terraform'
$cluster = (terraform -chdir="$tf" output -raw ecs_cluster).Trim()
$task = (terraform -chdir="$tf" output -raw ecs_schema_task_definition).Trim()
$subnets = @(terraform -chdir="$tf" output -json private_app_subnets | ConvertFrom-Json)
$sg = (terraform -chdir="$tf" output -raw worker_security_group).Trim()
$region = (terraform -chdir="$tf" output -raw region).Trim()
if (-not $cluster -or -not $task -or -not $sg -or $subnets.Count -lt 2) { throw 'Terraform outputs incomplete' }
$payload = @{
 cluster=$cluster; taskDefinition=$task; launchType='FARGATE'
 networkConfiguration=@{ awsvpcConfiguration=@{ subnets=$subnets; securityGroups=@($sg); assignPublicIp='DISABLED' } }
} | ConvertTo-Json -Depth 10
$tmp = [IO.Path]::GetTempFileName()
try {
  [IO.File]::WriteAllText($tmp, $payload, [System.Text.UTF8Encoding]::new($false))
  $out = aws ecs run-task --region $region --cli-input-json "file://$tmp" --output json | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0 -or $out.failures.Count -gt 0 -or $out.tasks.Count -lt 1) { throw ('Unable to run schema task: ' + ($out | ConvertTo-Json -Depth 5)) }
  $arn = $out.tasks[0].taskArn
  Write-Host "Waiting for schema task: $arn"
  aws ecs wait tasks-stopped --region $region --cluster $cluster --tasks $arn
  if ($LASTEXITCODE -ne 0) { throw 'Schema task did not finish in waiter deadline' }
  $result = aws ecs describe-tasks --region $region --cluster $cluster --tasks $arn --output json | ConvertFrom-Json
  $container = $result.tasks[0].containers | Select-Object -First 1
  if ($container.exitCode -ne 0) { throw "Schema initialization failed (exitCode=$($container.exitCode)). Read CloudWatch /aperturebridge/<environment>/worker." }
  Write-Host 'Database schema and application SQL permissions initialized.' -ForegroundColor Green
} finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
