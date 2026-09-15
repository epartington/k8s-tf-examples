variable "project_id" {
  type        = string
  description = "Existing GCP project ID."
}

variable "region" {
  type        = string
  description = "Region of the cluster / node subnet."
}

variable "state_bucket" {
  type        = string
  description = "GCS bucket holding remote state (to read the 10-network outputs)."
}

variable "zone" {
  type        = string
  description = "Zone for the zonal POV cluster. Leave empty to derive '<region>-a'. Set to make node placement explicit."
  default     = ""
}

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster."
  default     = "airs-gw-gke"
}

variable "node_count" {
  type        = number
  description = "Number of nodes in the node pool (total, for the zonal POV cluster)."
  default     = 2
}

variable "machine_type" {
  type        = string
  description = "Node machine type."
  default     = "n1-standard-4"
}

variable "node_disk_size_gb" {
  type        = number
  description = "Node boot disk size in GB."
  default     = 100
}

variable "node_disk_type" {
  type        = string
  description = "Node boot disk type."
  default     = "pd-balanced"
}

variable "release_channel" {
  type        = string
  description = "GKE release channel (RAPID, REGULAR, STABLE)."
  default     = "REGULAR"
}

variable "master_ipv4_cidr" {
  type        = string
  description = "The /28 range for the private control plane. Must match stage 10-network."
  default     = "172.16.0.0/28"
}

variable "authorized_networks" {
  type        = list(string)
  description = "CIDRs allowed to reach the public control-plane endpoint (operator / CI egress IPs) so Helm and kubectl can apply."
  default     = []
}
