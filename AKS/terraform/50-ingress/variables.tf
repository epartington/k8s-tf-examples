variable "subscription_id" {
  type        = string
  description = "Existing Azure subscription ID."
}

variable "location" {
  type        = string
  description = "Default region (provider only; resources use the 10-network region)."
}

variable "state_resource_group" {
  type        = string
  description = "Resource group of the state Storage Account (to read remote state)."
  default     = "airs-gw-tfstate-rg"
}

variable "storage_account" {
  type        = string
  description = "Storage Account holding remote state (10-network, 20-aks, 30-iam, 40-aigateway outputs)."
}

variable "container_name" {
  type        = string
  description = "Blob container holding remote state."
  default     = "tfstate"
}

variable "domain" {
  type        = string
  description = "FQDN for the gateway's TLS cert. Leave empty to derive '<appgw-public-ip>.nip.io'."
  default     = ""
}

variable "mcp_domain" {
  type        = string
  description = "FQDN for the MCP endpoint (added as a SAN on the same cert and routed to the MCP port via the same App Gateway/WAF). Leave empty to derive 'mcp.<gateway-domain>'. Only used when the gateway is deployed with MCP enabled (stage 40 server_mode 'all'/'mcp')."
  default     = ""
}

variable "allowed_source_ranges" {
  type        = list(string)
  description = "Source CIDRs allowed through the WAF policy to reach the gateway. Everything else is blocked (403). Empty leaves the WAF open (no allowlist rule)."
  default     = []
}

variable "gateway_port" {
  type        = number
  description = "Gateway container/service port used by the AGIC health probe."
  default     = 8787
}

variable "health_check_path" {
  type        = string
  description = "HTTP path the App Gateway health probe hits on the gateway."
  default     = "/v1/health"
}

variable "waf_policy_name" {
  type        = string
  description = "Name of the Application Gateway WAF policy."
  default     = "airs-gw-waf"
}

variable "appgw_name" {
  type        = string
  description = "Name of the Application Gateway (WAF_v2)."
  default     = "airs-gw-appgw"
}

variable "appgw_capacity" {
  type        = number
  description = "Application Gateway instance count."
  default     = 1
}

variable "appgw_identity_name" {
  type        = string
  description = "Name of the user-assigned managed identity the App Gateway uses to read the TLS cert from Key Vault."
  default     = "airs-gw-appgw-kv"
}

variable "key_vault_name" {
  type        = string
  description = "Name of the Key Vault holding the TLS cert. Must be globally unique (3-24 chars)."
  default     = "airs-gw-kv"
}

variable "cert_name" {
  type        = string
  description = "Name of the TLS certificate (in Key Vault and referenced by the App Gateway listener / Ingress annotation)."
  default     = "airs-gw-cert"
}

variable "tls_cert_keyvault_secret_id" {
  type        = string
  description = "Secret ID of an existing Key Vault certificate to use instead of generating a self-signed one. Leave empty to generate a self-signed cert for the derived domain."
  default     = ""
}

variable "ingress_name" {
  type        = string
  description = "Name of the Ingress object."
  default     = "airs-gw"
}

variable "ingress_class_name" {
  type        = string
  description = "Ingress class AGIC watches."
  default     = "azure-application-gateway"
}

# --- AGIC Helm install ---

variable "agic_chart_version" {
  type        = string
  description = "Version of the ingress-azure (AGIC) Helm chart. Leave empty for the latest published version."
  default     = ""
}

variable "agic_chart_repository" {
  type        = string
  description = "Helm repository for the AGIC chart."
  default     = "oci://mcr.microsoft.com/azure-application-gateway/charts"
}

variable "cluster_insecure_tls" {
  type        = bool
  description = "Skip TLS verification of the cluster API server endpoint for the kubernetes/helm providers. Set true ONLY when a TLS-inspecting proxy (corporate MITM) sits between the operator and the cluster, so the endpoint presents the proxy's cert instead of the AKS cluster CA. The client certificate still authenticates the request. Leave false for a normal secure connection."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all taggable resources (e.g. { CreatedBy = \"Eric Partington\" }). Set once in terraform.tfvars and passed to every stage."
  default     = {}
}
