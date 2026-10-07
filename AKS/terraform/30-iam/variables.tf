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

# --- Azure AI Foundry (model service) ---

variable "create_foundry" {
  type        = bool
  description = "Create the Azure AI Foundry (AIServices) account + a model deployment. Set false to reuse an existing account via foundry_account_id."
  default     = true
}

variable "foundry_account_id" {
  type        = string
  description = "Resource ID of an existing Azure AI Foundry (AIServices) account to grant the gateway access to (used only when create_foundry = false). Use the account ID (.../Microsoft.CognitiveServices/accounts/<name>); projects under it inherit account-level data-plane access."
  default     = ""
}

variable "foundry_endpoint" {
  type        = string
  description = "Endpoint of the existing Foundry account, surfaced via the foundry_endpoint output for the Portkey azure-ai provider. Used only when create_foundry = false; ignored otherwise (the created account's endpoint is used)."
  default     = ""
}

variable "foundry_account_name" {
  type        = string
  description = "Name of the Azure AI Foundry (AIServices) account to create (must be globally unique; used as the custom subdomain). Used only when create_foundry = true."
  default     = "airs-gw-foundry"
}

variable "foundry_location" {
  type        = string
  description = "Region for the Foundry account. Leave empty to use the 10-network region. Must be a region where your model is available."
  default     = ""
}

variable "foundry_deployment_name" {
  type        = string
  description = "Name of the model deployment to create."
  default     = "gpt-4o-mini"
}

variable "foundry_model_format" {
  type        = string
  description = "Publisher format of the deployed model: \"OpenAI\" for GPT models, or \"Meta\" / \"Mistral AI\" / \"DeepSeek\" / \"Microsoft\" / ... for other Foundry catalog families."
  default     = "OpenAI"
}

variable "foundry_model_name" {
  type        = string
  description = "Model to deploy from the Foundry catalog (e.g. gpt-4o-mini, Meta-Llama-3.1-8B-Instruct)."
  default     = "gpt-4o-mini"
}

variable "foundry_model_version" {
  type        = string
  description = "Model version to deploy. Leave empty to let Azure pick the default for the model."
  default     = ""
}

variable "foundry_capacity" {
  type        = number
  description = "Deployment capacity (thousands of tokens per minute, TPM units)."
  default     = 10
}

variable "model_access_roles" {
  type        = list(string)
  description = "Data-plane roles granted to the gateway identity on the Foundry account. \"Cognitive Services User\" covers the Foundry inference (/models) endpoint; \"Cognitive Services OpenAI User\" covers OpenAI-format calls."
  default     = ["Cognitive Services User", "Cognitive Services OpenAI User"]
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all taggable resources (e.g. { CreatedBy = \"Eric Partington\" }). Set once in terraform.tfvars and passed to every stage."
  default     = {}
}
