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

  # Foundry (AI Services) account to grant access to: the one we create, or a
  # supplied existing one.
  foundry_account_id = var.create_foundry ? azurerm_cognitive_account.foundry[0].id : var.foundry_account_id
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

# --- Azure AI Foundry (model service), gated by create_foundry ---
#
# kind = "AIServices" is the Azure AI Foundry inference resource: a single endpoint
# serving the full model catalog (OpenAI + Llama, Mistral, Phi, DeepSeek, ...), the
# Azure analog of Vertex Model Garden / Bedrock foundation models.

resource "azurerm_cognitive_account" "foundry" {
  count = var.create_foundry ? 1 : 0

  name                  = var.foundry_account_name
  location              = var.foundry_location != "" ? var.foundry_location : local.location
  resource_group_name   = local.rg
  kind                  = "AIServices"
  sku_name              = "S0"
  custom_subdomain_name = var.foundry_account_name
}

# One model deployment from the catalog. format "OpenAI" for GPT models, or
# "Meta" / "Mistral AI" / "DeepSeek" / ... for other catalog families.
resource "azurerm_cognitive_deployment" "model" {
  count = var.create_foundry ? 1 : 0

  name                 = var.foundry_deployment_name
  cognitive_account_id = azurerm_cognitive_account.foundry[0].id

  model {
    format  = var.foundry_model_format
    name    = var.foundry_model_name
    version = var.foundry_model_version != "" ? var.foundry_model_version : null
  }

  sku {
    name     = "Standard"
    capacity = var.foundry_capacity
  }
}

# Let the gateway identity call the model service keyless via Entra (mirrors
# roles/aiplatform.user / bedrock:InvokeModel). "Cognitive Services User" covers
# the Foundry inference (/models) endpoint; "Cognitive Services OpenAI User" covers
# OpenAI-format calls. Both are granted by default so either Portkey provider works.
resource "azurerm_role_assignment" "model_access" {
  for_each = local.foundry_account_id != "" ? toset(var.model_access_roles) : toset([])

  scope                = local.foundry_account_id
  role_definition_name = each.value
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
