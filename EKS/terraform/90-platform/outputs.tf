# ---------------------------------------------------------------------------
# PUBLIC CONTRACT for downstream (consumer) projects.
# Consumers read ONLY this stage's state (key "90-platform.tfstate") via
# terraform_remote_state. Treat these as a stable API: additive changes only —
# do not rename or remove outputs (that breaks consumers), even if the internal
# stages are refactored.
# ---------------------------------------------------------------------------

output "cloud" {
  description = "Cloud provider of this platform."
  value       = "eks"
}

output "region" {
  description = "AWS region."
  value       = local.eks.region
}

# --- Cluster ---
output "cluster_name" {
  description = "EKS cluster name."
  value       = local.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = local.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = local.eks.cluster_ca_certificate
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN (for consumer IRSA roles)."
  value       = local.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL (for consumer IRSA trust conditions)."
  value       = local.eks.oidc_provider_url
}

# --- Network ---
output "vpc_id" {
  description = "VPC ID."
  value       = local.net.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (node/workload placement)."
  value       = local.net.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs (internet-facing LBs)."
  value       = local.net.public_subnet_ids
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
output "gateway_role_arn" {
  description = "Gateway IRSA role ARN (Bedrock access)."
  value       = local.iam.gateway_role_arn
}

output "lb_controller_role_arn" {
  description = "AWS Load Balancer Controller IRSA role ARN."
  value       = local.iam.lb_controller_role_arn
}

output "model_backend" {
  description = "Model backend this platform proxies to."
  value       = "bedrock"
}

# --- Ingress / public endpoints ---
output "alb_hostname" {
  description = "ALB DNS name fronting the gateway."
  value       = local.ing.alb_hostname
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

output "waf_web_acl_arn" {
  description = "WAFv2 web ACL ARN on the ALB."
  value       = local.ing.waf_web_acl_arn
}
