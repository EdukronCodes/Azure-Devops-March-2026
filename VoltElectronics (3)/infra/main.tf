terraform {
  required_version = ">= 1.9, < 2.0"
  backend "azurerm" { use_azuread_auth = true }
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
  storage_use_azuread             = true
  subscription_id                 = var.subscription_id
}
variable "subscription_id" { type = string }
variable "trusted_public_ips" {
  type        = list(string)
  default     = []
  description = "Explicit public IPv4 addresses for deployment upload; VM access uses subnet service endpoints."
}
variable "location" {
  type    = string
  default = "eastus"
}
variable "app_name" {
  type    = string
  default = "volt-electronics"
}
variable "ssh_public_key" {
  type        = string
  description = "SSH public key only. Management uses Azure Run Command; no Internet SSH is permitted."
}
variable "app_vm_size" {
  type    = string
  default = "Standard_D2s_v4"
}
variable "sonar_vm_size" {
  type    = string
  default = "Standard_D2s_v4"
}
variable "enable_sonar_vm" {
  type    = bool
  default = true
}
resource "azurerm_resource_group" "platform" {
  name     = "${var.app_name}-rg"
  location = var.location
  tags     = { application = "volt", environment = "demo", managed_by = "terraform" }
}
module "network" {
  source              = "./modules/network"
  name                = var.app_name
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
}
module "application" {
  source              = "./modules/compute"
  name                = "${var.app_name}-app"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  subnet_id           = module.network.app_subnet_id
  public_endpoint     = true
  vm_size             = var.app_vm_size
  ssh_public_key      = var.ssh_public_key
  cloud_init          = file("${path.module}/cloud-init/host.yml")
}
module "sonarqube" {
  count               = var.enable_sonar_vm ? 1 : 0
  source              = "./modules/compute"
  name                = "${var.app_name}-sonar"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  subnet_id           = module.network.hub_subnet_id
  public_endpoint     = false
  vm_size             = var.sonar_vm_size
  ssh_public_key      = var.ssh_public_key
  cloud_init          = file("${path.module}/cloud-init/host.yml")
  depends_on          = [module.network]
}
module "releases" {
  source              = "./modules/releases"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  app_principal_id    = module.application.principal_id
  resource_group_id   = azurerm_resource_group.platform.id
  subnet_ids          = [module.network.app_subnet_id, module.network.hub_subnet_id]
  trusted_public_ips  = var.trusted_public_ips
  sonar_principal_id  = var.enable_sonar_vm ? module.sonarqube[0].principal_id : null
  enable_sonar        = var.enable_sonar_vm
}
output "url" { value = "http://${module.application.public_ip}" }
output "public_ip" { value = module.application.public_ip }
output "resource_group" { value = azurerm_resource_group.platform.name }
output "app_vm_name" { value = module.application.vm_name }
output "release_storage_account" { value = module.releases.storage_account_name }
output "sonar_vm_name" { value = var.enable_sonar_vm ? module.sonarqube[0].vm_name : "" }
output "sonarqube_private_url" { value = var.enable_sonar_vm ? "http://${module.sonarqube[0].private_ip}:9000" : "" }
