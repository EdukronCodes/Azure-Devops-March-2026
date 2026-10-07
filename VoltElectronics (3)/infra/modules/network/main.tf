variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
resource "azurerm_virtual_network" "hub" {
  name                = "${var.name}-hub-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = ["10.10.0.0/16"]
}
resource "azurerm_subnet" "shared" {
  name                 = "shared-services"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.1.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
}
resource "azurerm_virtual_network" "spoke" {
  for_each            = { app = "10.20.0.0/16", operations = "10.30.0.0/16" }
  name                = "${var.name}-${each.key}-spoke-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [each.value]
}
resource "azurerm_subnet" "spoke" {
  for_each             = { app = "10.20.1.0/24", operations = "10.30.1.0/24" }
  name                 = "${each.key}-workloads"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [each.value]
  service_endpoints    = ["Microsoft.Storage"]
}
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each                     = azurerm_virtual_network.spoke
  name                         = "hub-to-${each.key}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = each.value.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
}
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each                     = azurerm_virtual_network.spoke
  name                         = "${each.key}-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = each.value.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  use_remote_gateways          = false
}
resource "azurerm_network_security_group" "application" {
  name                = "${var.name}-app-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
}
# trivy:ignore:AVD-AZU-0047 Public HTTP/HTTPS is the requested demonstration endpoint; Internet SSH is not allowed.
resource "azurerm_network_security_rule" "public_web" {
  name                        = "PublicWeb"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.application.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443"]
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
}
resource "azurerm_network_security_rule" "deny_other_inbound" {
  name                        = "DenyOtherInbound"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.application.name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}
resource "azurerm_subnet_network_security_group_association" "application" {
  subnet_id                 = azurerm_subnet.spoke["app"].id
  network_security_group_id = azurerm_network_security_group.application.id
}
resource "azurerm_network_security_group" "shared" {
  name                = "${var.name}-shared-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
}
resource "azurerm_network_security_rule" "private_sonar" {
  name                        = "PrivateSonar"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.shared.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9000"
  source_address_prefixes     = ["10.10.0.0/16", "10.20.0.0/16", "10.30.0.0/16"]
  destination_address_prefix  = "*"
}
resource "azurerm_network_security_rule" "shared_deny" {
  name                        = "DenyOtherInbound"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.shared.name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}
resource "azurerm_subnet_network_security_group_association" "shared" {
  subnet_id                 = azurerm_subnet.shared.id
  network_security_group_id = azurerm_network_security_group.shared.id
}
resource "azurerm_public_ip" "nat" {
  name                = "${var.name}-hub-egress-ip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}
resource "azurerm_nat_gateway" "hub" {
  name                = "${var.name}-hub-egress"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "Standard"
}
resource "azurerm_nat_gateway_public_ip_association" "hub" {
  nat_gateway_id       = azurerm_nat_gateway.hub.id
  public_ip_address_id = azurerm_public_ip.nat.id
}
resource "azurerm_subnet_nat_gateway_association" "shared" {
  subnet_id      = azurerm_subnet.shared.id
  nat_gateway_id = azurerm_nat_gateway.hub.id
}
output "app_subnet_id" { value = azurerm_subnet.spoke["app"].id }
output "hub_subnet_id" { value = azurerm_subnet.shared.id }
