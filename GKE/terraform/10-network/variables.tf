variable "project_id" {
  type        = string
  description = "Existing GCP project ID."
}

variable "region" {
  type        = string
  description = "Region for the subnet, Cloud Router and Cloud NAT."
}

variable "network_name" {
  type        = string
  description = "Name of the isolated VPC to create."
  default     = "airs-gw-vpc"
}

variable "subnet_name" {
  type        = string
  description = "Name of the primary subnet that hosts GKE nodes."
  default     = "airs-gw-subnet"
}

variable "subnet_cidr" {
  type        = string
  description = "Primary CIDR range for the node subnet."
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  type        = string
  description = "Optional explicit secondary range for GKE pods. Leave empty to let GKE auto-allocate a Google-managed range."
  default     = ""
}

variable "services_cidr" {
  type        = string
  description = "Optional explicit secondary range for GKE services. Leave empty to let GKE auto-allocate a Google-managed range."
  default     = ""
}

variable "pods_range_name" {
  type        = string
  description = "Name of the pods secondary range (only used when pods_cidr is set)."
  default     = "pods"
}

variable "services_range_name" {
  type        = string
  description = "Name of the services secondary range (only used when services_cidr is set)."
  default     = "services"
}

variable "static_ip_name" {
  type        = string
  description = "Name of the global static IP reserved for the external HTTPS load balancer."
  default     = "airs-gw-ip"
}

variable "master_ipv4_cidr" {
  type        = string
  description = "The /28 range used by the private GKE control plane. Referenced by firewall rules; must match stage 20-gke."
  default     = "172.16.0.0/28"
}
