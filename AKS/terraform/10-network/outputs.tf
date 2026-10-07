output "resource_group_name" {
  description = "Name of the workload resource group (used by stages 20-50)."
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the workload resource group (role-assignment scope in stage 30)."
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Region of the workload resources."
  value       = azurerm_resource_group.main.location
}

output "vnet_id" {
  description = "ID of the VNet."
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "Name of the VNet."
  value       = azurerm_virtual_network.vnet.name
}

output "aks_subnet_id" {
  description = "ID of the AKS node subnet (stage 20 places the cluster here)."
  value       = azurerm_subnet.aks.id
}

output "nat_public_ip_address" {
  description = "NAT Gateway egress IP. Stage 20 adds this to the API server authorized ranges so nodes (which egress via NAT) can reach the public control plane."
  value       = azurerm_public_ip.nat.ip_address
}

output "appgw_subnet_id" {
  description = "ID of the Application Gateway subnet (stage 50)."
  value       = azurerm_subnet.appgw.id
}

output "appgw_public_ip_id" {
  description = "ID of the Application Gateway frontend public IP (stage 50)."
  value       = azurerm_public_ip.appgw.id
}

output "appgw_public_ip_address" {
  description = "The reserved App Gateway public IP address (seeds the nip.io domain / point DNS here)."
  value       = azurerm_public_ip.appgw.ip_address
}

output "appgw_public_ip_name" {
  description = "Name of the App Gateway frontend public IP."
  value       = azurerm_public_ip.appgw.name
}
