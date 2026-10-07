variable "region" {
  type        = string
  description = "AWS region."
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket holding remote state (to read the 20-eks outputs)."
}

variable "state_lock_table" {
  type        = string
  description = "DynamoDB table used for state locking."
  default     = "airs-gw-tflock"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name (used in IAM role names)."
  default     = "airs-gw-eks"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace the gateway runs in. Must match stage 40-aigateway."
  default     = "airs-gw"
}

variable "ksa_name" {
  type        = string
  description = "Kubernetes service account name for the gateway pod (IRSA subject). Must match stage 40-aigateway."
  default     = "gateway-sa"
}

variable "bedrock_model_arns" {
  type        = list(string)
  description = "Bedrock model ARNs the gateway may invoke. Default [\"*\"] allows any model (POV). Scope to specific model ARNs for production."
  default     = ["*"]
}

variable "lb_controller_namespace" {
  type        = string
  description = "Namespace the AWS Load Balancer Controller runs in (IRSA subject). Stage 50 installs the controller here."
  default     = "kube-system"
}

variable "lb_controller_sa_name" {
  type        = string
  description = "Service account name for the AWS Load Balancer Controller (IRSA subject). Stage 50 uses this as the chart SA."
  default     = "aws-load-balancer-controller"
}
