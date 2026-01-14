
output "vm_id" {
  description = "ID of the virtual machine"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "nic_id" {
  description = "Network Interface ID"
  value       = azurerm_network_interface.nic.id
}

output "principal_id" {
  description = "Principal ID of the VM's Managed Identity"
  value       = azurerm_linux_virtual_machine.vm.identity[0].principal_id
}
