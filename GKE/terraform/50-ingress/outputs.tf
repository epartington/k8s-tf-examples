output "ingress_ip" {
  description = "Static IP the external HTTPS load balancer serves on."
  value       = local.static_ip_address
}

output "gateway_domain" {
  description = "Domain on the managed cert (nip.io fallback when no domain was set)."
  value       = local.domain
}

output "gateway_url" {
  description = "Base URL for the gateway once DNS/cert are ready."
  value       = "https://${local.domain}"
}

output "security_policy_name" {
  description = "Cloud Armor security policy applied to the backend."
  value       = google_compute_security_policy.armor.name
}
