variable "project_id" {
  type        = string
  description = "Existing GCP project ID that hosts the cluster and Secret Manager secrets."
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

variable "chart_path" {
  type        = string
  description = "Path to the vendored airs-gw Helm chart, relative to this stage directory."
  default     = "../../docs/airs-gw-helm-main/charts/airs-gw"
}

variable "image_repository" {
  type        = string
  description = "Gateway image repository. Enterprise registry by default; docs/gcp.md uses docker.io/portkeyai/gateway_enterprise."
  default     = "registry.portkey.ai/airsgw/gateway_enterprise"
}

variable "image_tag" {
  type        = string
  description = "Gateway image tag (minimum supported 2.15.0)."
  default     = "2.21.0"
}

variable "registry_server" {
  type        = string
  description = "Registry host for the image pull secret (must match the registry your Portkey creds are issued for)."
  default     = "registry.portkey.ai"
}

variable "pull_secret_name" {
  type        = string
  description = "Name of the dockerconfigjson pull secret created in the namespace."
  default     = "airs-gw-registry"
}

variable "env_secret_name" {
  type        = string
  description = "Name of the Kubernetes Secret holding the Portkey control-plane credentials consumed by the chart."
  default     = "airs-gw-env"
}

variable "gateway_port" {
  type        = number
  description = "Gateway service/container port."
  default     = 8787
}

variable "backend_config_name" {
  type        = string
  description = "Name of the BackendConfig created in stage 50-ingress; referenced here via the Service annotation."
  default     = "airs-gw-backendconfig"
}

# --- Secret Manager secret IDs (values are read at apply time, never stored in tfvars) ---

variable "sm_aigw_client_auth" {
  type        = string
  description = "Secret Manager secret ID holding PORTKEY_CLIENT_AUTH (the hybrid license key)."
  default     = "aigw-client-auth"
}

variable "sm_organisations_to_sync" {
  type        = string
  description = "Secret Manager secret ID holding ORGANISATIONS_TO_SYNC (the Portkey org ID)."
  default     = "aigw-org-id"
}

variable "sm_docker_username" {
  type        = string
  description = "Secret Manager secret ID holding the registry username."
  default     = "aigw-docker-user"
}

variable "sm_docker_password" {
  type        = string
  description = "Secret Manager secret ID holding the registry password."
  default     = "aigw-docker-pass"
}
