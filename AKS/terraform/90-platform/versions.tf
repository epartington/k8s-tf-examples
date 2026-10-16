terraform {
  required_version = ">= 1.5.0"

  # Read-only aggregation stage: reads the other stages' remote state and
  # re-exports a curated, stable output set. No providers/resources — just the
  # built-in terraform_remote_state data source and outputs.
  #
  # resource_group_name and storage_account_name are passed at init via -backend-config.
  backend "azurerm" {
    container_name = "tfstate"
    key            = "90-platform.tfstate"
  }
}
