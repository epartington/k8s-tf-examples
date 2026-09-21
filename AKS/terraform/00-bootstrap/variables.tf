variable "subscription_id" {
  type        = string
  description = "Existing Azure subscription ID that will host the POV. Terraform registers providers here but does not create the subscription."
}

variable "location" {
  type        = string
  description = "Azure region for the state resource group + storage account (e.g. canadacentral)."
}

variable "state_resource_group" {
  type        = string
  description = "Name of the resource group to create for the Terraform state Storage Account. Reused by every later stage at init via -backend-config=\"resource_group_name=...\"."
  default     = "airs-gw-tfstate-rg"
}

variable "storage_account" {
  type        = string
  description = "Name of the Storage Account to create for remote Terraform state. Must be globally unique, 3-24 lowercase alphanumerics. Reused as the backend storage account by every other stage."
}

variable "container_name" {
  type        = string
  description = "Blob container that holds the state files (one key per stage). Must match the container_name hardcoded in each stage's backend block."
  default     = "tfstate"
}

variable "register_providers" {
  type        = bool
  description = "Register the Azure resource providers the later stages depend on. Set false if they are already registered on the subscription (registration requires subscription-level rights)."
  default     = true
}

variable "resource_providers" {
  type        = list(string)
  description = "Azure resource providers to register for the POV."
  default = [
    "Microsoft.ContainerService",
    "Microsoft.Network",
    "Microsoft.CognitiveServices",
    "Microsoft.ManagedIdentity",
    "Microsoft.KeyVault",
  ]
}
