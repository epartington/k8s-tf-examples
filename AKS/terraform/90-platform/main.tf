# Reads every stage's remote state so 90-platform can re-export a single, stable
# output contract for downstream (consumer) projects. Add new stages' reads here.
locals {
  backend = {
    resource_group_name  = var.state_resource_group
    storage_account_name = var.storage_account
    container_name       = var.container_name
  }
}

data "terraform_remote_state" "network" {
  backend = "azurerm"
  config  = merge(local.backend, { key = "10-network.tfstate" })
}

data "terraform_remote_state" "aks" {
  backend = "azurerm"
  config  = merge(local.backend, { key = "20-aks.tfstate" })
}

data "terraform_remote_state" "iam" {
  backend = "azurerm"
  config  = merge(local.backend, { key = "30-iam.tfstate" })
}

data "terraform_remote_state" "gateway" {
  backend = "azurerm"
  config  = merge(local.backend, { key = "40-aigateway.tfstate" })
}

data "terraform_remote_state" "ingress" {
  backend = "azurerm"
  config  = merge(local.backend, { key = "50-ingress.tfstate" })
}

locals {
  net = data.terraform_remote_state.network.outputs
  aks = data.terraform_remote_state.aks.outputs
  iam = data.terraform_remote_state.iam.outputs
  gw  = data.terraform_remote_state.gateway.outputs
  ing = data.terraform_remote_state.ingress.outputs
}
