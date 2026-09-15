variable "project_id" {
  type        = string
  description = "Existing GCP project ID."
}

variable "region" {
  type        = string
  description = "Default region (provider only)."
}

variable "state_bucket" {
  type        = string
  description = "GCS bucket holding remote state (10-network, 20-gke, 40-portkey outputs)."
}

variable "domain" {
  type        = string
  description = "FQDN for the gateway's managed TLS cert. Leave empty to derive '<static-ip>.nip.io'."
  default     = ""
}

variable "mcp_domain" {
  type        = string
  description = "FQDN for the MCP endpoint (added as a SAN on the same managed cert and routed to the MCP port via the same ALB/Cloud Armor). Leave empty to derive 'mcp.<gateway-domain>'. Only used when the gateway is deployed with MCP enabled (stage 40 server_mode 'all'/'mcp')."
  default     = ""
}

variable "allowed_source_ranges" {
  type        = list(string)
  description = "Source CIDRs allowed through Cloud Armor to reach the gateway. Everything else is denied (403)."
  default     = []
}

variable "iap_enabled" {
  type        = bool
  description = "Enable IAP on the backend. Off by default: IAP requires OIDC tokens and would block plain API calls. Cloud Armor is the primary POV control."
  default     = false
}

variable "gateway_port" {
  type        = number
  description = "Gateway container/service port used by the backend health check."
  default     = 8787
}

variable "health_check_path" {
  type        = string
  description = "HTTP path the LB health check probes on the gateway."
  default     = "/v1/health"
}

variable "security_policy_name" {
  type        = string
  description = "Name of the Cloud Armor security policy."
  default     = "airs-gw-armor"
}

variable "managed_cert_name" {
  type        = string
  description = "Name of the Google-managed SSL certificate (referenced as pre-shared-cert by the Ingress)."
  default     = "airs-gw-cert"
}

variable "ingress_name" {
  type        = string
  description = "Name of the Ingress object."
  default     = "airs-gw"
}

# --- IAP scaffold (only used when iap_enabled = true) ---

variable "iap_support_email" {
  type        = string
  description = "Support email for the IAP OAuth brand. Required when iap_enabled = true."
  default     = ""
}

variable "iap_oauth_secret_name" {
  type        = string
  description = "Name of the Kubernetes Secret holding the IAP OAuth client credentials (client_id/client_secret)."
  default     = "airs-gw-iap-oauth"
}
