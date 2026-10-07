variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "vm_size" { type = string }
variable "ssh_public_key" { type = string }
variable "cloud_init" { type = string }
variable "public_endpoint" { type = bool }
resource "azurerm_public_ip" "web" {
  count               = var.public_endpoint ? 1 : 0
  name                = "${var.name}-ip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}
resource "azurerm_network_interface" "vm" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  ip_configuration {
    name                          = "private"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.public_endpoint ? azurerm_public_ip.web[0].id : null
  }
}
resource "azurerm_linux_virtual_machine" "vm" {
  name                                                   = var.name
  resource_group_name                                    = var.resource_group_name
  location                                               = var.location
  size                                                   = var.vm_size
  admin_username                                         = "voltadmin"
  network_interface_ids                                  = [azurerm_network_interface.vm.id]
  disable_password_authentication                        = true
  disk_controller_type                                   = "SCSI"
  encryption_at_host_enabled                             = true
  patch_mode                                             = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = true
  custom_data                                            = base64encode(var.cloud_init)
  # Cloud-init runs only at first boot. Software releases are managed by Run Command.
  # Ignore template text differences to preserve VM identity and attached data disks.
  lifecycle { ignore_changes = [custom_data] }
  identity { type = "SystemAssigned" }
  admin_ssh_key {
    username   = "voltadmin"
    public_key = var.ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 32
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  boot_diagnostics {}
}
resource "azurerm_managed_disk" "data" {
  name                 = "${var.name}-data"
  resource_group_name  = var.resource_group_name
  location             = var.location
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 64
  lifecycle { prevent_destroy = true }
}
resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  lun                = 0
  caching            = "None"
}
output "vm_name" { value = azurerm_linux_virtual_machine.vm.name }
output "principal_id" { value = azurerm_linux_virtual_machine.vm.identity[0].principal_id }
output "private_ip" { value = azurerm_network_interface.vm.private_ip_address }
output "public_ip" { value = var.public_endpoint ? azurerm_public_ip.web[0].ip_address : "" }
