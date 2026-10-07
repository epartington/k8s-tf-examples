terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }

  backend "gcs" {
    prefix = "40-aigateway"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Short-lived OAuth token used to authenticate the kubernetes/helm providers
# against the cluster's public control-plane endpoint (locked by authorized
# networks in stage 20-gke).
data "google_client_config" "default" {}

# When cluster_insecure_tls is true (TLS-inspecting proxy between operator and
# cluster), skip verification and omit the cluster CA — the endpoint presents the
# proxy's cert, not the GKE cluster CA. The bearer token still authenticates.
provider "kubernetes" {
  host                   = "https://${data.terraform_remote_state.gke.outputs.endpoint}"
  token                  = data.google_client_config.default.access_token
  insecure               = var.cluster_insecure_tls
  cluster_ca_certificate = var.cluster_insecure_tls ? null : base64decode(data.terraform_remote_state.gke.outputs.ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.terraform_remote_state.gke.outputs.endpoint}"
    token                  = data.google_client_config.default.access_token
    insecure               = var.cluster_insecure_tls
    cluster_ca_certificate = var.cluster_insecure_tls ? null : base64decode(data.terraform_remote_state.gke.outputs.ca_certificate)
  }
}
