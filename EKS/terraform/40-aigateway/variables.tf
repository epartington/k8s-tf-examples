variable "region" {
  type        = string
  description = "AWS region. Also set as AWS_REGION on the gateway for the Bedrock SDK."
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket holding remote state (to read the 20-eks and 30-iam outputs)."
}

variable "state_lock_table" {
  type        = string
  description = "DynamoDB table used for state locking."
  default     = "airs-gw-tflock"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for the gateway. Must match stage 30-iam."
  default     = "airs-gw"
}

variable "ksa_name" {
  type        = string
  description = "Kubernetes service account name for the gateway pod. Must match stage 30-iam's IRSA subject."
  default     = "gateway-sa"
}

variable "helm_release_name" {
  type        = string
  description = "Helm release name. Drives the chart fullname (Service = <release>, Redis = <release>-redis)."
  default     = "airs-gw"
}

variable "chart_repository" {
  type        = string
  description = "Helm repository URL for the airs-gw chart."
  default     = "https://portkey-ai.github.io/airs-gw-helm"
}

variable "chart_name" {
  type        = string
  description = "Chart name within the repository."
  default     = "airs-gw"
}

variable "chart_version" {
  type        = string
  description = "airs-gw chart version to install. Pinned to a known-good version for reproducible applies; set to \"\" to pull the latest published chart."
  default     = "1.2.0"
}

variable "image_overrides" {
  type        = map(map(string))
  description = "Per-image overrides merged onto the chart's images block, e.g. { gatewayImage = { tag = \"2.22.0\" } } or { dataserviceImage = { repository = \"...\", tag = \"1.10.0\" } }. Lets you run newer images on top of the pinned chart_version without changing the chart. Keys: gatewayImage, dataserviceImage, redisImage, minioImage, minioClientImage, etcdImage, milvusImage. Wins over image_repository/image_tag for the same image."
  default     = {}
}

variable "values_file" {
  type        = string
  description = "Path to the values.yaml downloaded from the AI Gateway console (carries the Portkey credentials). Defaults to values.yaml in this stage directory (40-aigateway), so simply placing the downloaded file there works. See values.yaml.example."
  default     = ""
}

variable "image_repository" {
  type        = string
  description = "Override the gateway image repository. Leave empty to use whatever the console values.yaml / chart specify."
  default     = ""
}

variable "image_tag" {
  type        = string
  description = "Override the gateway image tag. Leave empty to use the version pinned by the console values.yaml / chart appVersion. Set only to hotfix a specific tag (minimum supported 2.15.0)."
  default     = ""
}

variable "gateway_port" {
  type        = number
  description = "Gateway service/container port."
  default     = 8787
}

variable "server_mode" {
  type        = string
  description = "Chart SERVER_MODE. 'all' runs both the gateway (gateway_port) and the MCP server (mcp_port) in one pod; 'mcp' runs only MCP; '' runs only the gateway. The POV uses 'all' so both are fronted by the stage-50 ALB."
  default     = "all"

  validation {
    condition     = contains(["all", "mcp", ""], var.server_mode)
    error_message = "server_mode must be one of: \"all\", \"mcp\", or \"\" (gateway only)."
  }
}

variable "mcp_port" {
  type        = number
  description = "MCP service/container port (chart MCP_PORT). Exposed on the same Service as the gateway when server_mode is 'all' or 'mcp'."
  default     = 8788
}

variable "cluster_insecure_tls" {
  type        = bool
  description = "Skip TLS verification of the cluster API server endpoint for the kubernetes/helm providers. Set true ONLY when a TLS-inspecting proxy (corporate MITM) sits between the operator and the cluster, so the endpoint presents the proxy's cert instead of the EKS cluster CA. The bearer token still authenticates the request. Leave false for a normal secure connection."
  default     = false
}
