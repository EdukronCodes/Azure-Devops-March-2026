param(
  [string]$Organization='https://dev.azure.com/edukrondevops',
  [string]$Project='VoltElectronics',
  [int]$PipelineId=13,
  [string]$SubscriptionId='c2383fdd-26a3-44a8-9d61-2c7f2e1e08bf',
  [string]$Location='centralindia',
  [string]$AppResourceGroup='volt-electronics-rg',
  [string]$StateResourceGroup='volt-electronics-tfstate-rg',
  [string]$StateStorageAccount='voltstatec2383fdd'
)
$ErrorActionPreference='Stop'
function Check-Azure { if ($LASTEXITCODE -ne 0) { throw 'Azure/DevOps command failed; stopping federation setup.' } }
$account = az account show -o json | ConvertFrom-Json
Check-Azure
if ($account.user.name -ne 'giftzee.online@gmail.com' -or $account.id -ne $SubscriptionId) { throw 'Select the intended Giftzee account and subscription first.' }
$identityName='volt-electronics-pipeline'
$connectionName='volt-electronics-azure-wif'
$identity=az identity create --name $identityName --resource-group $StateResourceGroup --location $Location -o json | ConvertFrom-Json
Check-Azure
$projectId=az devops project show --organization $Organization --project $Project --query id -o tsv
Check-Azure
$connections=az devops service-endpoint list --organization $Organization --project $Project -o json | ConvertFrom-Json
Check-Azure
$connection=$connections | Where-Object name -eq $connectionName | Select-Object -First 1
if (-not $connection) {
  $configuration=@{
    name=$connectionName; type='AzureRM'; url='https://management.azure.com/'; isShared=$false; isReady=$true
    data=@{subscriptionId=$SubscriptionId;subscriptionName=$account.name;environment='AzureCloud';scopeLevel='Subscription';creationMode='Manual'}
    authorization=@{scheme='WorkloadIdentityFederation';parameters=@{tenantid=$account.tenantId;serviceprincipalid=$identity.clientId}}
    serviceEndpointProjectReferences=@(@{projectReference=@{id=$projectId;name=$Project};name=$connectionName})
  }
  $temporaryConfig=Join-Path $env:TEMP ('volt-service-connection-'+[guid]::NewGuid()+'.json')
  $configuration | ConvertTo-Json -Depth 12 | Set-Content $temporaryConfig
  try {
    $connection=az devops service-endpoint create --organization $Organization --project $Project --service-endpoint-configuration $temporaryConfig -o json | ConvertFrom-Json
    Check-Azure
  } finally { Remove-Item -LiteralPath $temporaryConfig -ErrorAction SilentlyContinue }
}
$parameters=$connection.authorization.parameters
if (-not $parameters.workloadIdentityFederationIssuer -or -not $parameters.workloadIdentityFederationSubject) { throw 'Azure DevOps did not return federation claims.' }
az identity federated-credential create --name volt-devops --identity-name $identityName --resource-group $StateResourceGroup --issuer $parameters.workloadIdentityFederationIssuer --subject $parameters.workloadIdentityFederationSubject --audiences api://AzureADTokenExchange -o none
Check-Azure
# Resource management is limited to the two project resource groups.
$stateScope="/subscriptions/$SubscriptionId/resourceGroups/$StateResourceGroup"
$appScope="/subscriptions/$SubscriptionId/resourceGroups/$AppResourceGroup"
foreach ($assignment in @(@{role='Contributor';scope=$stateScope},@{role='Storage Blob Data Contributor';scope="$stateScope/providers/Microsoft.Storage/storageAccounts/$StateStorageAccount"},@{role='Contributor';scope=$appScope},@{role='Storage Blob Data Reader';scope=$appScope},@{role='Role Based Access Control Administrator';scope=$appScope})) {
  az role assignment create --assignee-object-id $identity.principalId --assignee-principal-type ServicePrincipal --role $assignment.role --scope $assignment.scope -o none
  Check-Azure
}
$permissionFile=Join-Path $env:TEMP ('volt-pipeline-permission-'+[guid]::NewGuid()+'.json')
@{pipelines=@(@{id=$PipelineId;authorized=$true})} | ConvertTo-Json -Depth 6 | Set-Content $permissionFile
try {
  az devops invoke --organization $Organization --area pipelinePermissions --resource pipelinePermissions --route-parameters project=$Project resourceType=endpoint "resourceId=$($connection.id)" --http-method PATCH --in-file $permissionFile --api-version 7.1-preview -o none
  Check-Azure
} finally { Remove-Item -LiteralPath $permissionFile -ErrorAction SilentlyContinue }
Write-Host "Federated connection configured: $connectionName; only pipeline $PipelineId is authorized."
