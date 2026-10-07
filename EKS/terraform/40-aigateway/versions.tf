terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

  # bucket, dynamodb_table, and region are passed at init via -backend-config.
  backend "s3" {
    key = "40-aigateway.tfstate"
  }
}

provider "aws" {
  region = var.region
}

locals {
  eks = data.terraform_remote_state.eks.outputs
}

# Short-lived token for the EKS API server (refreshed each plan/apply).
data "aws_eks_cluster_auth" "this" {
  name = local.eks.cluster_name
}

# When cluster_insecure_tls is true (TLS-inspecting proxy between operator and
# cluster), skip verification and omit the cluster CA — the endpoint presents the
# proxy's cert, not the EKS CA. The bearer token still authenticates.
provider "kubernetes" {
  host                   = local.eks.cluster_endpoint
  cluster_ca_certificate = var.cluster_insecure_tls ? null : base64decode(local.eks.cluster_ca_certificate)
  insecure               = var.cluster_insecure_tls
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = local.eks.cluster_endpoint
    cluster_ca_certificate = var.cluster_insecure_tls ? null : base64decode(local.eks.cluster_ca_certificate)
    insecure               = var.cluster_insecure_tls
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
