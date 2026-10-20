variable "subscription_id" {
  type        = string
  description = "Existing Azure subscription ID."
}

variable "location" {
  type        = string
  description = "Default region (provider only)."
}

variable "state_resource_group" {
  type        = string
  description = "Resource group of the state Storage Account (to read remote state)."
  default     = "airs-gw-tfstate-rg"
}

variable "storage_account" {
  type        = string
  description = "Storage Account holding remote state (to read the 20-aks and 30-iam outputs)."
}

variable "container_name" {
  type        = string
  description = "Blob container holding remote state."
  default     = "tfstate"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for the gateway. Must match stage 30-iam."
  default     = "airs-gw"
}

variable "ksa_name" {
  type        = string
  description = "Kubernetes service account name for the gateway pod. Must match stage 30-iam's federated credential."
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
  description = "Chart SERVER_MODE. 'all' runs both the gateway (gateway_port) and the MCP server (mcp_port) in one pod; 'mcp' runs only MCP; '' runs only the gateway. The POV uses 'all' so both are fronted by the stage-50 Application Gateway."
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

variable "mcp_gateway_base_url" {
  type        = string
  description = "External base URL (scheme + host, no path) the MCP server advertises in its OAuth protected-resource metadata, e.g. https://mcp.example.com. REQUIRED when the gateway sits behind a TLS-terminating proxy (App Gateway) that forwards HTTP — otherwise the server derives the metadata 'resource' from the inbound (http) scheme and MCP OAuth clients reject the http/https mismatch. Leave empty for a direct/standalone deploy. Sets the chart's MCP_GATEWAY_BASE_URL env."
  default     = ""
}

variable "cluster_insecure_tls" {
  type        = bool
  description = "Skip TLS verification of the cluster API server endpoint for the kubernetes/helm providers. Set true ONLY when a TLS-inspecting proxy (corporate MITM) sits between the operator and the cluster, so the endpoint presents the proxy's cert instead of the AKS cluster CA. The client certificate still authenticates the request. Leave false for a normal secure connection."
  default     = false
}

# --- Datadog OTEL (optional) — ported from EKS ---

variable "enable_datadog_otel" {
  type        = bool
  description = "Run a Datadog Agent sidecar in the gateway pod and push OTLP (APM traces, aggregated analytics, AI Observability) to it on localhost:4318. The sidecar is required because the gateway targets loopback. Default off."
  default     = false
}

variable "otel_endpoint" {
  type        = string
  description = "OTLP endpoint the gateway pushes to. For the sidecar pattern leave as the in-pod Datadog Agent (localhost:4318)."
  default     = "http://localhost:4318"
}

variable "otel_service_name" {
  type        = string
  description = "OTEL_SERVICE_NAME on the gateway. Set to \"portkey\" to match the GenAI exporter's hardcoded service.name (first-wins via the Agent) so analytics + per-request GenAI spans collapse into one Datadog service."
  default     = "portkey"
}

variable "datadog_site" {
  type        = string
  description = "Datadog site the Agent sidecar ships to (e.g. datadoghq.com, datadoghq.eu, us3.datadoghq.com)."
  default     = "datadoghq.com"
}

variable "datadog_service" {
  type        = string
  description = "DD_SERVICE tag on the Datadog Agent sidecar."
  default     = "airs-gw"
}

variable "datadog_env" {
  type        = string
  description = "Datadog environment tag (DD_ENV on the sidecar + deployment.environment resource attrs on the GenAI spans)."
  default     = "azure"
}

variable "otel_trusted_custom_hosts" {
  type        = string
  description = "Value for the gateway's TRUSTED_CUSTOM_HOSTS when Datadog is enabled. MUST include the loopback set or the gateway's SSRF guard blocks the OTLP push to the sidecar. Host-only match REPLACES the built-in defaults, so append any other hosts you rely on."
  default     = "localhost,127.0.0.1,::1"
}

variable "datadog_api_key" {
  type        = string
  description = "Datadog API key. Stored in the datadog-otel cluster Secret. Set in the gitignored terraform.tfvars."
  default     = ""
  sensitive   = true
}

variable "datadog_secret_name" {
  type        = string
  description = "Name of the Kubernetes Secret holding the Datadog API key under key dd_api_key (referenced by the gateway + sidecar)."
  default     = "datadog-otel"
}

variable "datadog_agent_image" {
  type        = string
  description = "Datadog Agent image for the sidecar."
  default     = "gcr.io/datadoghq/agent:7"
}
