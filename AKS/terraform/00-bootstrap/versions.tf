terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Bootstrap uses LOCAL state on purpose: it creates the Storage Account that
  # every other stage uses as its azurerm backend. Do not add a backend block here.
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
