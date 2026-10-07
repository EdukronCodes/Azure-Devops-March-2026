param(
  [string]$SubscriptionId='c2383fdd-26a3-44a8-9d61-2c7f2e1e08bf',
  [string]$BootstrapStorage='voltstatec2383fdd',
  [string]$StorageName='voltstateusc2383fdd',
  [string]$Location='eastus',
  [string]$PipelinePrincipalId=''
)
$ErrorActionPreference='Stop'
function Check-Command { if ($LASTEXITCODE -ne 0) { throw 'Backend command failed; migration stopped.' } }
$account=az account show -o json | ConvertFrom-Json
Check-Command
if ($account.user.name -ne 'giftzee.online@gmail.com' -or $account.id -ne $SubscriptionId) { throw 'Select the Giftzee account and subscription first.' }
if (-not $PipelinePrincipalId) {
  $PipelinePrincipalId=az identity show --name volt-electronics-pipeline --resource-group volt-electronics-tfstate-rg --query principalId -o tsv
  Check-Command
}
$operatorIp=(Invoke-RestMethod https://api.ipify.org).Trim()
$env:TF_VAR_subscription_id=$SubscriptionId
$env:TF_VAR_storage_name=$StorageName
$env:TF_VAR_location=$Location
$env:TF_VAR_pipeline_principal_id=$PipelinePrincipalId
$env:TF_VAR_trusted_public_ips=ConvertTo-Json -Compress -InputObject @($operatorIp)
az storage account network-rule add --account-name $BootstrapStorage --resource-group volt-electronics-tfstate-rg --ip-address $operatorIp -o none
Check-Command
@"
resource_group_name = "volt-electronics-tfstate-rg"
storage_account_name = "$BootstrapStorage"
container_name = "tfstate"
key = "volt-electronics/ci-backend.tfstate"
use_azuread_auth = true
"@ | Set-Content infra/ci-backend/backend.hcl
terraform -chdir=infra/ci-backend init '-backend-config=backend.hcl' -input=false
Check-Command
terraform -chdir=infra/ci-backend plan '-out=backend.tfplan' -input=false
Check-Command
terraform -chdir=infra/ci-backend apply -input=false backend.tfplan
Check-Command
@"
resource_group_name = "volt-electronics-tfstate-rg"
storage_account_name = "$StorageName"
container_name = "tfstate"
key = "volt-electronics/app.tfstate"
use_azuread_auth = true
"@ | Set-Content infra/backend.hcl
# Copy state through Terraform's migration flow; the original account is retained.
terraform -chdir=infra init -migrate-state -force-copy '-backend-config=backend.hcl' -input=false
Check-Command
Write-Host 'Protected CI backend created and application state migrated. Update pipeline stateStorageAccount to the new account.'
