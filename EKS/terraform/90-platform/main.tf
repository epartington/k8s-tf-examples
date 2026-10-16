# Reads every stage's remote state so 90-platform can re-export a single, stable
# output contract for downstream (consumer) projects. Add new stages' reads here.
locals {
  backend = {
    bucket         = var.state_bucket
    region         = var.region
    dynamodb_table = var.state_lock_table
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config  = merge(local.backend, { key = "10-network.tfstate" })
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config  = merge(local.backend, { key = "20-eks.tfstate" })
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config  = merge(local.backend, { key = "30-iam.tfstate" })
}

data "terraform_remote_state" "gateway" {
  backend = "s3"
  config  = merge(local.backend, { key = "40-aigateway.tfstate" })
}

data "terraform_remote_state" "ingress" {
  backend = "s3"
  config  = merge(local.backend, { key = "50-ingress.tfstate" })
}

locals {
  net = data.terraform_remote_state.network.outputs
  eks = data.terraform_remote_state.eks.outputs
  iam = data.terraform_remote_state.iam.outputs
  gw  = data.terraform_remote_state.gateway.outputs
  ing = data.terraform_remote_state.ingress.outputs
}
