variable "subscription_id" {
  type        = string
  description = "Existing Azure subscription ID."
}

variable "location" {
  type        = string
  description = "Default region (provider only; identities use the 10-network region)."
}

variable "state_resource_group" {
  type        = string
  description = "Resource group of the state Storage Account (to read remote state)."
  default     = "airs-gw-tfstate-rg"
}

variable "storage_account" {
  type        = string
  description = "Storage Account holding remote state (to read the 10-network and 20-aks outputs)."
}

variable "container_name" {
  type        = string
  description = "Blob container holding remote state."
  default     = "tfstate"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace the gateway runs in. Must match stage 40-aigateway."
  default     = "airs-gw"
}

variable "ksa_name" {
  type        = string
  description = "Kubernetes service account name for the gateway pod. Must match stage 40-aigateway."
  default     = "gateway-sa"
}

variable "gateway_identity_name" {
  type        = string
  description = "Name of the user-assigned managed identity bound to the gateway pod."
  default     = "airs-gw-gateway"
}

# --- AGIC identity (consumed by stage 50's Helm AGIC install) ---

variable "agic_identity_name" {
  type        = string
  description = "Name of the user-assigned managed identity used by AGIC to manage the Application Gateway."
  default     = "airs-gw-agic"
}

variable "agic_namespace" {
  type        = string
  description = "Namespace AGIC runs in (its service account is federated to this managed identity). Must match stage 50."
  default     = "default"
}

variable "agic_ksa_name" {
  type        = string
  description = "AGIC service account name (the AGIC Helm chart's SA). Must match stage 50."
  default     = "ingress-azure"
}

# --- Azure OpenAI (model service) ---

variable "create_openai" {
  type        = bool
  description = "Create the Azure OpenAI (Cognitive Services) account + a model deployment. Set false to reuse an existing account via openai_account_id."
  default     = true
}

variable "openai_account_id" {
  type        = string
  description = "Resource ID of an existing Azure OpenAI account to grant the gateway access to (used only when create_openai = false)."
  default     = ""
}

variable "openai_account_name" {
  type        = string
  description = "Name of the Azure OpenAI account to create (must be globally unique; used as the custom subdomain). Used only when create_openai = true."
  default     = "airs-gw-openai"
}

variable "openai_location" {
  type        = string
  description = "Region for the Azure OpenAI account. Leave empty to use the 10-network region. Must be a region where your model is available."
  default     = ""
}

variable "openai_deployment_name" {
  type        = string
  description = "Name of the model deployment to create."
  default     = "gpt-4o-mini"
}

variable "openai_model_name" {
  type        = string
  description = "Model to deploy."
  default     = "gpt-4o-mini"
}

variable "openai_model_version" {
  type        = string
  description = "Model version to deploy. Leave empty to let Azure pick the default for the model."
  default     = ""
}

variable "openai_capacity" {
  type        = number
  description = "Deployment capacity (thousands of tokens per minute, TPM units)."
  default     = 10
}
