# ---------------------------------------------------------------------------
# PUBLIC CONTRACT for downstream (consumer) projects.
# Consumers read ONLY this stage's state (prefix "90-platform") via
# terraform_remote_state. Treat these as a stable API: additive changes only —
# do not rename or remove outputs (that breaks consumers), even if the internal
# stages are refactored.
# ---------------------------------------------------------------------------

output "cloud" {
  description = "Cloud provider of this platform."
  value       = "gke"
}

output "location" {
  description = "Cluster location (zone for the zonal POV cluster)."
  value       = local.gke.location
}

# --- Cluster ---
output "cluster_name" {
  description = "GKE cluster name."
  value       = local.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE control-plane endpoint."
  value       = local.gke.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = local.gke.ca_certificate
  sensitive   = true
}

output "workload_pool" {
  description = "Workload Identity pool <project>.svc.id.goog (for consumer WI bindings)."
  value       = local.gke.workload_pool
}

# --- Network ---
output "network_self_link" {
  description = "VPC self link."
  value       = local.net.network_self_link
}

output "subnet_self_link" {
  description = "Node subnet self link."
  value       = local.net.subnet_self_link
}

output "static_ip_address" {
  description = "Reserved global static IP for the external LB."
  value       = local.net.static_ip_address
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
output "gateway_gsa_email" {
  description = "Gateway Google service account email (Workload Identity)."
  value       = local.iam.gsa_email
}

output "model_backend" {
  description = "Model backend this platform proxies to."
  value       = "vertex-ai"
}

output "vertex_project_id" {
  description = "Vertex AI project ID the gateway can call."
  value       = local.iam.vertex_project_id
}

output "vertex_region" {
  description = "Vertex AI region."
  value       = local.iam.vertex_region
}

# --- Ingress / public endpoints ---
output "ingress_ip" {
  description = "Static IP the external HTTPS load balancer serves on."
  value       = local.ing.ingress_ip
}

output "gateway_domain" {
  description = "Gateway hostname on the managed cert."
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

output "security_policy_name" {
  description = "Cloud Armor security policy on the gateway backend."
  value       = local.ing.security_policy_name
}
