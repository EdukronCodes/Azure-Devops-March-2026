terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}
provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
  storage_use_azuread             = true
  subscription_id                 = var.subscription_id
}
variable "subscription_id" { type = string }
variable "location" {
  type    = string
  default = "centralindia"
}
variable "storage_name" { type = string }
variable "trusted_public_ips" { type = list(string) }
resource "azurerm_resource_group" "state" {
  name     = "volt-electronics-tfstate-rg"
  location = var.location
}
resource "azurerm_storage_account" "state" {
  depends_on                      = [azurerm_role_assignment.state]
  name                            = var.storage_name
  resource_group_name             = azurerm_resource_group.state.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = var.trusted_public_ips
  }
  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 30 }
  }
  lifecycle { prevent_destroy = true }
}
data "azurerm_client_config" "current" {}
resource "azurerm_role_assignment" "state" {
  scope                = azurerm_resource_group.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
output "storage_account_name" { value = azurerm_storage_account.state.name }
output "resource_group_name" { value = azurerm_resource_group.state.name }
