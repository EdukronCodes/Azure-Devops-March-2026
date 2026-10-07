variable "resource_group_name" { type = string }
variable "resource_group_id" { type = string }
data "azurerm_client_config" "current" {}
variable "location" { type = string }
variable "subnet_ids" { type = list(string) }
variable "trusted_public_ips" { type = list(string) }
variable "app_principal_id" { type = string }
variable "sonar_principal_id" {
  type    = string
  default = null
}
variable "enable_sonar" {
  type    = bool
  default = false
}
resource "random_string" "suffix" {
  length  = 10
  upper   = false
  special = false
}
resource "azurerm_storage_account" "release" {
  depends_on                      = [azurerm_role_assignment.uploader]
  name                            = "volt${random_string.suffix.result}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.trusted_public_ips
    virtual_network_subnet_ids = var.subnet_ids
  }
  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 30 }
  }
}
resource "azurerm_storage_container" "release" {
  name                  = "releases"
  storage_account_id    = azurerm_storage_account.release.id
  container_access_type = "private"
}
resource "azurerm_role_assignment" "app" {
  scope                = azurerm_storage_account.release.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.app_principal_id
}
resource "azurerm_role_assignment" "uploader" {
  scope                = var.resource_group_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
resource "azurerm_role_assignment" "sonar" {
  count                = var.enable_sonar ? 1 : 0
  scope                = azurerm_storage_account.release.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.sonar_principal_id
}
output "storage_account_name" { value = azurerm_storage_account.release.name }
