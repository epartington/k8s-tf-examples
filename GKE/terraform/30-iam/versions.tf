terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7.0"
    }
  }

  backend "gcs" {
    prefix = "30-iam"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
