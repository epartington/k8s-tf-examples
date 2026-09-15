variable "project_id" {
  type        = string
  description = "Existing GCP project ID that will host the POV. Terraform enables APIs here but does not create the project."
}

variable "region" {
  type        = string
  description = "Default GCP region for regional resources (e.g. us-central1)."
}

variable "state_bucket" {
  type        = string
  description = "Name of the GCS bucket to create for remote Terraform state. Must be globally unique. Reused as the backend bucket by every other stage."
}

variable "activate_apis" {
  type        = list(string)
  description = "Project APIs to enable for the POV."
  default = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "iap.googleapis.com",
    "aiplatform.googleapis.com",
    "certificatemanager.googleapis.com",
    "storage.googleapis.com",
  ]
}

variable "disable_services_on_destroy" {
  type        = bool
  description = "Whether to disable the enabled APIs when this stage is destroyed. Keep false to avoid breaking other resources during teardown."
  default     = false
}
