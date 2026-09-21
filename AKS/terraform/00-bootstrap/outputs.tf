output "resource_group_name" {
  description = "Resource group holding the state Storage Account. Pass to later stages' init via -backend-config=\"resource_group_name=<this>\"."
  value       = azurerm_resource_group.state.name
}

output "storage_account_name" {
  description = "Storage Account holding remote state for all later stages. Pass to init via -backend-config=\"storage_account_name=<this>\"."
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Blob container that holds the per-stage state files."
  value       = azurerm_storage_container.tfstate.name
}
