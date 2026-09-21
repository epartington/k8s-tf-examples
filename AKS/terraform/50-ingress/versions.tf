terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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

  backend "azurerm" {
    container_name = "tfstate"
    key            = "50-ingress.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

locals {
  aks = data.terraform_remote_state.aks.outputs
}

# When cluster_insecure_tls is true (TLS-inspecting proxy between operator and
# cluster), skip verification and omit the cluster CA — the endpoint presents the
# proxy's cert, not the AKS CA. The client certificate still authenticates.
provider "kubernetes" {
  host                   = local.aks.host
  client_certificate     = base64decode(local.aks.client_certificate)
  client_key             = base64decode(local.aks.client_key)
  insecure               = var.cluster_insecure_tls
  cluster_ca_certificate = var.cluster_insecure_tls ? null : base64decode(local.aks.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = local.aks.host
    client_certificate     = base64decode(local.aks.client_certificate)
    client_key             = base64decode(local.aks.client_key)
    insecure               = var.cluster_insecure_tls
    cluster_ca_certificate = var.cluster_insecure_tls ? null : base64decode(local.aks.cluster_ca_certificate)
  }
}
