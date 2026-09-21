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

output "openai_account_id" {
  description = "Resource ID of the Azure OpenAI account the gateway can call (created or supplied)."
  value       = local.openai_account_id
}

output "openai_endpoint" {
  description = "Endpoint of the created Azure OpenAI account (empty when create_openai = false)."
  value       = var.create_openai ? azurerm_cognitive_account.openai[0].endpoint : ""
}

output "openai_deployment_name" {
  description = "Name of the created model deployment (empty when create_openai = false)."
  value       = var.create_openai ? azurerm_cognitive_deployment.model[0].name : ""
}
