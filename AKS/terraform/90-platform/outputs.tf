# ---------------------------------------------------------------------------
# PUBLIC CONTRACT for downstream (consumer) projects.
# Consumers read ONLY this stage's state (key "90-platform.tfstate") via
# terraform_remote_state. Treat these as a stable API: additive changes only —
# do not rename or remove outputs (that breaks consumers), even if the internal
# stages are refactored.
# ---------------------------------------------------------------------------

output "cloud" {
  description = "Cloud provider of this platform."
  value       = "aks"
}

output "location" {
  description = "Azure region."
  value       = local.aks.location
}

output "resource_group_name" {
  description = "Workload resource group."
  value       = local.net.resource_group_name
}

# --- Cluster ---
output "cluster_name" {
  description = "AKS cluster name."
  value       = local.aks.cluster_name
}

output "node_resource_group" {
  description = "Auto-generated node resource group (MC_...)."
  value       = local.aks.node_resource_group
}

output "cluster_host" {
  description = "AKS API server endpoint."
  value       = local.aks.host
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = local.aks.cluster_ca_certificate
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL (for consumer Workload Identity federation)."
  value       = local.aks.oidc_issuer_url
}

# --- Network ---
output "vnet_id" {
  description = "VNet ID."
  value       = local.net.vnet_id
}

output "aks_subnet_id" {
  description = "Node subnet ID."
  value       = local.net.aks_subnet_id
}

output "appgw_subnet_id" {
  description = "Application Gateway subnet ID."
  value       = local.net.appgw_subnet_id
}

# --- Gateway (app) ---
output "gateway_namespace" {
  description = "Namespace the AI gateway runs in."
  value       = local.gw.namespace
}

output "gateway_service" {
  description = "Gateway ClusterIP Service name."
  value       = local.gw.service_name
}

output "gateway_service_port" {
  description = "Gateway Service port."
  value       = local.gw.service_port
}

output "mcp_enabled" {
  description = "Whether the MCP server is exposed."
  value       = local.gw.mcp_enabled
}

output "mcp_service_port" {
  description = "MCP Service port (when enabled)."
  value       = local.gw.mcp_service_port
}

# --- Identity / model service ---
output "gateway_identity_client_id" {
  description = "Gateway managed-identity client ID (Workload Identity)."
  value       = local.iam.gateway_identity_client_id
}

output "model_backend" {
  description = "Model backend this platform proxies to."
  value       = "azure-foundry"
}

output "foundry_account_id" {
  description = "Azure AI Foundry (AIServices) account resource ID."
  value       = local.iam.foundry_account_id
}

output "foundry_endpoint" {
  description = "Foundry endpoint for the Portkey azure-ai provider."
  value       = local.iam.foundry_endpoint
}

output "foundry_deployment_name" {
  description = "Model deployment name on the Foundry account."
  value       = local.iam.foundry_deployment_name
}

# --- Ingress / public endpoints ---
output "ingress_ip" {
  description = "Public IP the Application Gateway serves on."
  value       = local.ing.ingress_ip
}

output "gateway_domain" {
  description = "Gateway hostname on the TLS cert."
  value       = local.ing.gateway_domain
}

output "gateway_url" {
  description = "Base URL for the gateway."
  value       = local.ing.gateway_url
}

output "mcp_domain" {
  description = "MCP hostname (empty when MCP disabled)."
  value       = local.ing.mcp_domain
}

output "mcp_url" {
  description = "Base URL for the MCP endpoint (empty when MCP disabled)."
  value       = local.ing.mcp_url
}

output "waf_policy_name" {
  description = "WAF policy applied to the Application Gateway."
  value       = local.ing.waf_policy_name
}
