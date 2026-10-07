param([Parameter(Mandatory)][string]$SubscriptionId,[Parameter(Mandatory)][string]$StorageName,[string]$Location='centralindia')
$ErrorActionPreference='Stop'
function Assert-Success { if ($LASTEXITCODE -ne 0) { throw 'Command failed; stopping bootstrap.' } }
$bootstrapIdentity = az account show --query user.name -o tsv
Assert-Success
if ($bootstrapIdentity.Trim().ToLowerInvariant() -ne 'giftzee.online@gmail.com') { throw 'Sign in as giftzee.online@gmail.com before provisioning.' }
$bootstrapPublicIp = (Invoke-RestMethod https://api.ipify.org).Trim()
if ($bootstrapPublicIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw 'A public IPv4 address is required for the backend firewall.' }
$env:TF_VAR_trusted_public_ips = ConvertTo-Json -Compress -InputObject @($bootstrapPublicIp)
az account set --subscription $SubscriptionId
Assert-Success
foreach ($bootstrapProvider in @('Microsoft.Resources','Microsoft.Storage','Microsoft.Authorization','Microsoft.Network','Microsoft.Compute','Microsoft.ManagedIdentity')) {
  az provider register --namespace $bootstrapProvider
  Assert-Success
}
terraform -chdir=infra/bootstrap init
Assert-Success
terraform -chdir=infra/bootstrap apply "-var=subscription_id=$SubscriptionId" "-var=storage_name=$StorageName" "-var=location=$Location" -auto-approve
Assert-Success
# Data-plane RBAC propagation can take several minutes. Re-run the next command if needed.
az storage container create --account-name $StorageName --name tfstate --auth-mode login
Assert-Success
@"
resource_group_name = "volt-electronics-tfstate-rg"
storage_account_name = "$StorageName"
container_name = "tfstate"
key = "volt-electronics/app.tfstate"
use_azuread_auth = true
"@ | Set-Content infra/backend.hcl
terraform -chdir=infra init '-backend-config=backend.hcl'
Assert-Success
# Preserve the bootstrap state in its own remote key after the backend exists.
@'
terraform {
  backend "azurerm" {}
}
'@ | Set-Content infra/bootstrap/backend.tf
terraform -chdir=infra/bootstrap init -migrate-state -force-copy -backend-config="resource_group_name=volt-electronics-tfstate-rg" -backend-config="storage_account_name=$StorageName" -backend-config="container_name=tfstate" -backend-config="key=volt-electronics/bootstrap.tfstate" -backend-config="use_azuread_auth=true"
Assert-Success
