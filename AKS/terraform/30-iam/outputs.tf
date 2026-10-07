output "gateway_identity_client_id" {
  description = "Client ID of the gateway managed identity (used for the KSA annotation in stage 40)."
  value       = azurerm_user_assigned_identity.gateway.client_id
}

output "gateway_identity_id" {
  description = "Resource ID of the gateway managed identity."
  value       = azurerm_user_assigned_identity.gateway.id
}

output "gateway_identity_principal_id" {
  description = "Principal (object) ID of the gateway managed identity."
  value       = azurerm_user_assigned_identity.gateway.principal_id
}

output "namespace" {
  description = "Namespace the gateway federated credential targets."
  value       = var.namespace
}

output "ksa_name" {
  description = "KSA name the gateway federated credential targets."
  value       = var.ksa_name
}

output "agic_identity_client_id" {
  description = "Client ID of the AGIC managed identity (used by the AGIC Helm install in stage 50)."
  value       = azurerm_user_assigned_identity.agic.client_id
}

output "agic_identity_id" {
  description = "Resource ID of the AGIC managed identity."
  value       = azurerm_user_assigned_identity.agic.id
}

output "agic_namespace" {
  description = "Namespace AGIC runs in (federated credential subject). Stage 50 installs AGIC here."
  value       = var.agic_namespace
}

output "agic_ksa_name" {
  description = "AGIC service account name (federated credential subject). Stage 50 uses this as the chart SA."
  value       = var.agic_ksa_name
}

output "foundry_account_id" {
  description = "Resource ID of the Azure AI Foundry (AIServices) account the gateway can call (created or supplied)."
  value       = local.foundry_account_id
}

output "foundry_endpoint" {
  description = "Foundry endpoint for the Portkey azure-ai provider — the created account's endpoint, or foundry_endpoint when reusing an existing account."
  value       = var.create_foundry ? azurerm_cognitive_account.foundry[0].endpoint : var.foundry_endpoint
}

output "foundry_deployment_name" {
  description = "Model deployment name — the created deployment, or foundry_deployment_name when reusing an existing account."
  value       = var.create_foundry ? azurerm_cognitive_deployment.model[0].name : var.foundry_deployment_name
}
