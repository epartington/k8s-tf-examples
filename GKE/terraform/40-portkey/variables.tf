variable "project_id" {
  type        = string
  description = "Existing GCP project ID that hosts the cluster."
}

variable "region" {
  type        = string
  description = "Default region (provider only)."
}

variable "state_bucket" {
  type        = string
  description = "GCS bucket holding remote state (to read the 20-gke and 30-iam outputs)."
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for the gateway. Must match stage 30-iam."
  default     = "airs-gw"
}

variable "ksa_name" {
  type        = string
  description = "Kubernetes service account name for the gateway pod. Must match stage 30-iam's WI binding."
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
  description = "Chart version to install. Leave empty to pull the latest published version. Pin for reproducible applies."
  default     = ""
}

variable "values_file" {
  type        = string
  description = "Path to the values.yaml downloaded from the AI Gateway console (carries the Portkey credentials). Defaults to values.yaml in this stage directory (40-portkey), so simply placing the downloaded file there works. See values.yaml.example."
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

variable "backend_config_name" {
  type        = string
  description = "Name of the BackendConfig created in stage 50-ingress; referenced here via the Service annotation."
  default     = "airs-gw-backendconfig"
}
