variable "project_id" {
  type        = string
  description = "Project that hosts the GKE cluster (owns the Workload Identity pool)."
}

variable "region" {
  type        = string
  description = "Default region (provider only)."
}

variable "model_project_id" {
  type        = string
  description = "Project that serves the Vertex AI models. Defaults to project_id when empty. Supports cross-project Vertex access."
  default     = ""
}

variable "gsa_name" {
  type        = string
  description = "Short name (account_id) of the Google service account bound to the gateway pod."
  default     = "airs-gw-gateway"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace the gateway runs in. Must match stage 40-portkey."
  default     = "airs-gw"
}

variable "ksa_name" {
  type        = string
  description = "Kubernetes service account name for the gateway pod. Must match stage 40-portkey."
  default     = "gateway-sa"
}
