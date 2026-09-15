terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7.0"
    }
  }

  # Bootstrap uses LOCAL state on purpose: it creates the GCS bucket that every
  # other stage uses as its backend. Do not add a gcs backend block here.
}

provider "google" {
  project = var.project_id
  region  = var.region
}
