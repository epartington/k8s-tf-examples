output "namespace" {
  description = "Namespace the gateway runs in."
  value       = kubernetes_namespace.airs.metadata[0].name
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.airs_gw.name
}

output "service_name" {
  description = "Gateway ClusterIP Service name (chart fullname = release name). Target for the stage 50 Ingress."
  value       = var.helm_release_name
}

output "service_port" {
  description = "Gateway Service port."
  value       = var.gateway_port
}

output "mcp_enabled" {
  description = "Whether the MCP server is enabled (SERVER_MODE 'all' or 'mcp'). Stage 50 fronts the MCP port only when true."
  value       = local.mcp_enabled
}

output "mcp_service_port" {
  description = "MCP Service port on the gateway Service (exposed when mcp_enabled). Target for the stage 50 MCP host rule."
  value       = var.mcp_port
}

output "backend_config_name" {
  description = "BackendConfig name referenced by the Service annotation (created in stage 50-ingress)."
  value       = var.backend_config_name
}
