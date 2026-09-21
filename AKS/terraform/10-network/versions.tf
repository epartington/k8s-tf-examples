terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Partial backend: supply the storage account + resource group at init, e.g.
  #   terraform init \
  #     -backend-config="resource_group_name=<state_rg>" \
  #     -backend-config="storage_account_name=<storage_account>"
  backend "azurerm" {
    container_name = "tfstate"
    key            = "10-network.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
