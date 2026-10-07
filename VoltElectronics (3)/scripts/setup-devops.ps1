param(
  [Parameter(Mandatory)][string]$Organization,
  [string]$Project='VoltElectronics',
  [Parameter(Mandatory)][string]$ServiceConnection,
  [Parameter(Mandatory)][string]$SubscriptionId,
  [Parameter(Mandatory)][string]$AppName,
  [Parameter(Mandatory)][string]$StateStorageAccount,
  [Parameter(Mandatory)][string]$SshPublicKey,
  [string]$Location='centralindia'
)
$ErrorActionPreference='Stop'
function Check-Exit { if ($LASTEXITCODE -ne 0) { throw 'Azure DevOps command failed. Authenticate and verify access before retrying.' } }
if ($Organization -notmatch '^https://dev\.azure\.com/[^/]+/?$') { throw 'Use the exact https://dev.azure.com/ORGANIZATION URL.' }
$identity = az account show --query user.name -o tsv
Check-Exit
if ($identity.Trim().ToLowerInvariant() -ne 'giftzee.online@gmail.com') { throw "CLI identity is $identity. Sign in to giftzee.online@gmail.com before continuing." }
az devops project show --organization $Organization --project $Project --query id -o tsv 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  az devops project create --organization $Organization --name $Project --visibility private -o none
  Check-Exit
}
$repoId = az repos list --organization $Organization --project $Project --query "[?name=='VoltElectronics'].id | [0]" -o tsv
Check-Exit
if (-not $repoId) {
  $repoId = az repos create --organization $Organization --project $Project --name VoltElectronics --query id -o tsv
  Check-Exit
}
$remote = az repos show --organization $Organization --project $Project --repository $repoId --query remoteUrl -o tsv
Check-Exit
Write-Host "Repository: $remote"
Write-Host 'Commit and push this project to the main branch before continuing. This script does not change your local Git history.'
az repos ref list --organization $Organization --project $Project --repository $repoId --filter heads/main --query '[0].name' -o tsv | Tee-Object -Variable mainBranch
Check-Exit
if (-not $mainBranch) { throw "Push main to $remote, then run this script again." }
$endpoints = az devops service-endpoint list --organization $Organization --project $Project -o json | ConvertFrom-Json
Check-Exit
$connection = $endpoints | Where-Object name -eq $ServiceConnection | Select-Object -First 1
if (-not $connection -or $connection.authorization.scheme -ne 'WorkloadIdentityFederation') { throw 'Create the named Azure Resource Manager workload-identity service connection first.' }
$definitions = az pipelines list --organization $Organization --project $Project --name VoltElectronics -o json | ConvertFrom-Json
Check-Exit
$pipeline = $definitions | Select-Object -First 1
if (-not $pipeline) {
  $pipeline = az pipelines create --organization $Organization --project $Project --name VoltElectronics --repository $repoId --repository-type tfsgit --branch main --yml-path azure-pipelines.yml --skip-first-run -o json | ConvertFrom-Json
  Check-Exit
}
$values = @{
  azureServiceConnection=$ServiceConnection
  subscriptionId=$SubscriptionId
  appName=$AppName
  azureLocation=$Location
  stateResourceGroup='volt-electronics-tfstate-rg'
  stateStorageAccount=$StateStorageAccount
  sshPublicKey=$SshPublicKey
}
$existing = az pipelines variable list --organization $Organization --project $Project --pipeline-id $pipeline.id -o json | ConvertFrom-Json
Check-Exit
foreach ($entry in $values.GetEnumerator()) {
  if ($existing.PSObject.Properties.Name -contains $entry.Key) {
    az pipelines variable update --organization $Organization --project $Project --pipeline-id $pipeline.id --name $entry.Key --value $entry.Value -o none
  } else {
    az pipelines variable create --organization $Organization --project $Project --pipeline-id $pipeline.id --name $entry.Key --value $entry.Value -o none
  }
  Check-Exit
}
$policies = az repos policy list --organization $Organization --project $Project --repository-id $repoId --branch main -o json | ConvertFrom-Json
Check-Exit
$policy = $policies | Where-Object { $_.settings.buildDefinitionId -eq $pipeline.id } | Select-Object -First 1
if (-not $policy) {
  az repos policy build create --organization $Organization --project $Project --repository-id $repoId --branch main --build-definition-id $pipeline.id --display-name 'VoltElectronics PR validation' --enabled true --blocking true --manual-queue-only false --queue-on-source-update-only true --valid-duration 0 -o none
  Check-Exit
}
Write-Host "Pipeline ID: $($pipeline.id)"
Write-Host "Pipeline: $Organization/$Project/_build?definitionId=$($pipeline.id)"
Write-Host 'Authorize the federated connection for this pipeline. Queue only one deployment-enabled build at a time.'
Write-Host "Run: az pipelines run --organization $Organization --project $Project --id $($pipeline.id) --branch main"
