output "ingress_ip" {
  description = "Public IP the Application Gateway serves on."
  value       = local.appgw_public_ip_addr
}

output "gateway_domain" {
  description = "Domain on the TLS cert (nip.io fallback when no domain was set)."
  value       = local.domain
}

output "gateway_url" {
  description = "Base URL for the gateway once DNS/cert are ready."
  value       = "https://${local.domain}"
}

output "mcp_domain" {
  description = "MCP hostname on the TLS cert (empty when MCP is disabled in stage 40)."
  value       = local.mcp_enabled ? local.mcp_domain : ""
}

output "mcp_url" {
  description = "Base URL for the MCP endpoint once DNS/cert are ready (empty when MCP is disabled)."
  value       = local.mcp_enabled ? "https://${local.mcp_domain}" : ""
}

output "waf_policy_name" {
  description = "WAF policy applied to the Application Gateway (covers both the gateway and MCP hosts)."
  value       = azurerm_web_application_firewall_policy.waf.name
}
