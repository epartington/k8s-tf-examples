# Resource group that holds the remote-state Storage Account.
resource "azurerm_resource_group" "state" {
  name     = var.state_resource_group
  location = var.location
}

# Register the resource providers the rest of the stages depend on.
resource "azurerm_resource_provider_registration" "this" {
  for_each = var.register_providers ? toset(var.resource_providers) : toset([])

  name = each.value
}

# Remote-state Storage Account used as the azurerm backend by stages 10-50.
resource "azurerm_storage_account" "tfstate" {
  name                     = var.storage_account
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Blob container that holds one state file per stage (key = "<stage>.tfstate").
resource "azurerm_storage_container" "tfstate" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}
