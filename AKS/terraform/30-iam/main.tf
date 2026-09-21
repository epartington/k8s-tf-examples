data "terraform_remote_state" "network" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group
    storage_account_name = var.storage_account
    container_name       = var.container_name
    key                  = "10-network.tfstate"
  }
}

data "terraform_remote_state" "aks" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group
    storage_account_name = var.storage_account
    container_name       = var.container_name
    key                  = "20-aks.tfstate"
  }
}

locals {
  rg          = data.terraform_remote_state.network.outputs.resource_group_name
  rg_id       = data.terraform_remote_state.network.outputs.resource_group_id
  location    = data.terraform_remote_state.network.outputs.location
  oidc_issuer = data.terraform_remote_state.aks.outputs.oidc_issuer_url

  # OpenAI account to grant access to: the one we create, or a supplied existing one.
  openai_account_id = var.create_openai ? azurerm_cognitive_account.openai[0].id : var.openai_account_id
}

# --- Gateway pod identity (Workload Identity) ---

resource "azurerm_user_assigned_identity" "gateway" {
  name                = var.gateway_identity_name
  location            = local.location
  resource_group_name = local.rg
}

# Federate the gateway KSA to the managed identity via the cluster OIDC issuer.
resource "azurerm_federated_identity_credential" "gateway" {
  name                = "airs-gw-gateway-fic"
  resource_group_name = local.rg
  parent_id           = azurerm_user_assigned_identity.gateway.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = local.oidc_issuer
  subject             = "system:serviceaccount:${var.namespace}:${var.ksa_name}"
}

# --- Azure OpenAI (model service), gated by create_openai ---

resource "azurerm_cognitive_account" "openai" {
  count = var.create_openai ? 1 : 0

  name                  = var.openai_account_name
  location              = var.openai_location != "" ? var.openai_location : local.location
  resource_group_name   = local.rg
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = var.openai_account_name
}

resource "azurerm_cognitive_deployment" "model" {
  count = var.create_openai ? 1 : 0

  name                 = var.openai_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version != "" ? var.openai_model_version : null
  }

  sku {
    name     = "Standard"
    capacity = var.openai_capacity
  }
}

# Let the gateway identity call the model service (mirrors roles/aiplatform.user).
resource "azurerm_role_assignment" "openai_user" {
  count = local.openai_account_id != "" ? 1 : 0

  scope                = local.openai_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.gateway.principal_id
}

# --- AGIC identity (used by the Helm AGIC install in stage 50) ---

resource "azurerm_user_assigned_identity" "agic" {
  name                = var.agic_identity_name
  location            = local.location
  resource_group_name = local.rg
}

resource "azurerm_federated_identity_credential" "agic" {
  name                = "airs-gw-agic-fic"
  resource_group_name = local.rg
  parent_id           = azurerm_user_assigned_identity.agic.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = local.oidc_issuer
  subject             = "system:serviceaccount:${var.agic_namespace}:${var.agic_ksa_name}"
}

# AGIC mutates the Application Gateway config; grant it Contributor on the
# workload RG (POV-scoped). Tighten to the App Gateway resource for production.
resource "azurerm_role_assignment" "agic_contributor" {
  scope                = local.rg_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.agic.principal_id
}
