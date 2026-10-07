mock_provider "azurerm" {}

run "hub_spoke_network" {
  command = plan
  module { source = "./modules/network" }
  variables {
    name                = "volt-test"
    resource_group_name = "volt-test-rg"
    location            = "centralindia"
  }
  assert {
    condition     = azurerm_virtual_network.hub.address_space == toset(["10.10.0.0/16"]) && length(azurerm_virtual_network.spoke) == 2
    error_message = "Architecture requires one hub and two distinct spokes."
  }
  assert {
    condition     = azurerm_subnet.spoke["app"].address_prefixes == tolist(["10.20.1.0/24"]) && azurerm_subnet.spoke["operations"].address_prefixes == tolist(["10.30.1.0/24"])
    error_message = "Application and operations workloads must have separate address ranges."
  }
  assert {
    condition     = length(azurerm_virtual_network_peering.hub_to_spoke) == 2 && length(azurerm_virtual_network_peering.spoke_to_hub) == 2
    error_message = "Each spoke requires peering in both directions."
  }
  assert {
    condition     = azurerm_network_security_rule.private_sonar.destination_port_range == "9000" && azurerm_network_security_rule.private_sonar.source_address_prefix == null
    error_message = "SonarQube ingress must use the private source allowlist."
  }
}

run "public_application_compute" {
  command = plan
  module { source = "./modules/compute" }
  variables {
    name                = "volt-app-test"
    resource_group_name = "volt-test-rg"
    location            = "centralindia"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/volt-test-rg/providers/Microsoft.Network/virtualNetworks/test/subnets/app"
    vm_size             = "Standard_B2s"
    ssh_public_key      = file("tests/fixture-public-key.txt")
    cloud_init          = "#cloud-config\n"
    public_endpoint     = true
  }
  assert {
    condition     = length(azurerm_public_ip.web) == 1 && azurerm_linux_virtual_machine.vm.disable_password_authentication && azurerm_linux_virtual_machine.vm.encryption_at_host_enabled
    error_message = "The app needs a public endpoint with password authentication disabled and host encryption enabled."
  }
  assert {
    condition     = azurerm_virtual_machine_data_disk_attachment.data.lun == 0 && azurerm_managed_disk.data.disk_size_gb >= 64
    error_message = "SQLite must persist on the separate managed LUN 0 disk."
  }
}

run "private_sonarqube_compute" {
  command = plan
  module { source = "./modules/compute" }
  variables {
    name                = "volt-sonar-test"
    resource_group_name = "volt-test-rg"
    location            = "centralindia"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/volt-test-rg/providers/Microsoft.Network/virtualNetworks/test/subnets/shared"
    vm_size             = "Standard_D2s_v5"
    ssh_public_key      = file("tests/fixture-public-key.txt")
    cloud_init          = "#cloud-config\n"
    public_endpoint     = false
  }
  assert {
    condition     = length(azurerm_public_ip.web) == 0 && azurerm_network_interface.vm.ip_configuration[0].public_ip_address_id == null
    error_message = "SonarQube must have no public IP."
  }
}
