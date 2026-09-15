terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7.0"
    }
  }

  # Partial backend: supply the bucket at init time, e.g.
  #   terraform init -backend-config="bucket=<state_bucket>"
  backend "gcs" {
    prefix = "10-network"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
