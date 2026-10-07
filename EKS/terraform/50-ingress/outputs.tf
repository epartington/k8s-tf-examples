output "alb_hostname" {
  description = "DNS name of the provisioned ALB. CNAME your domain here, or reach it directly (with a Host header for host-based routing)."
  value       = try(kubernetes_ingress_v1.gateway.status[0].load_balancer[0].ingress[0].hostname, "")
}

output "gateway_domain" {
  description = "Host the gateway is served on (self-signed cert CN). CNAME this to alb_hostname, or use --resolve."
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

output "waf_web_acl_arn" {
  description = "ARN of the WAFv2 web ACL associated with the ALB (covers both the gateway and MCP hosts)."
  value       = aws_wafv2_web_acl.this.arn
}
