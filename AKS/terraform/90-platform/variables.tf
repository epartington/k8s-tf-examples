variable "state_resource_group" {
  type        = string
  description = "Resource group of the state Storage Account (to read remote state)."
  default     = "airs-gw-tfstate-rg"
}

variable "storage_account" {
  type        = string
  description = "Storage Account holding remote state for all stages."
}

variable "container_name" {
  type        = string
  description = "Blob container holding remote state."
  default     = "tfstate"
}
