variable "subscription_id" {
  type        = string
  description = "Existing Azure subscription ID."
}

variable "location" {
  type        = string
  description = "Default region (provider only; the cluster uses the 10-network region)."
}

variable "state_resource_group" {
  type        = string
  description = "Resource group of the state Storage Account (to read the 10-network outputs via remote state)."
  default     = "airs-gw-tfstate-rg"
}

variable "storage_account" {
  type        = string
  description = "Storage Account holding remote state (to read the 10-network outputs)."
}

variable "container_name" {
  type        = string
  description = "Blob container holding remote state."
  default     = "tfstate"
}

variable "cluster_name" {
  type        = string
  description = "Name of the AKS cluster."
  default     = "airs-gw-aks"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the cluster. Leave empty to use the region default."
  default     = ""
}

variable "node_count" {
  type        = number
  description = "Number of nodes in the system node pool."
  default     = 2
}

variable "vm_size" {
  type        = string
  description = "Node VM size."
  default     = "Standard_D4s_v5"
}

variable "node_disk_size_gb" {
  type        = number
  description = "Node OS disk size in GB."
  default     = 100
}

variable "authorized_networks" {
  type        = list(string)
  description = "CIDRs allowed to reach the public API server endpoint (operator / CI egress IPs) so Helm and kubectl can apply. Empty leaves the API server open."
  default     = []
}
