variable "region" {
  type        = string
  description = "AWS region of the cluster."
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket holding remote state (to read the 10-network outputs)."
}

variable "state_lock_table" {
  type        = string
  description = "DynamoDB table used for state locking."
  default     = "airs-gw-tflock"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Must match the subnet tags in stage 10-network."
  default     = "airs-gw-eks"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version (e.g. 1.30). Leave empty to use the EKS default."
  default     = ""
}

variable "node_count" {
  type        = number
  description = "Number of nodes in the managed node group (desired = min = max for the POV)."
  default     = 2
}

variable "instance_type" {
  type        = string
  description = "Node instance type. m5.xlarge is 4 vCPU / 16 GB (matches the GKE/AKS node spec)."
  default     = "m5.xlarge"
}

variable "node_disk_size_gb" {
  type        = number
  description = "Node root volume size in GB."
  default     = 100
}

variable "authorized_networks" {
  type        = list(string)
  description = "CIDRs allowed to reach the public API server endpoint (operator / CI egress IPs) so Helm and kubectl can apply. Empty opens it to 0.0.0.0/0."
  default     = []
}
