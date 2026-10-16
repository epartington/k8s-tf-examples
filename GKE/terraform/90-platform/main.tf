# Reads every stage's remote state so 90-platform can re-export a single, stable
# output contract for downstream (consumer) projects. Add new stages' reads here.
data "terraform_remote_state" "network" {
  backend = "gcs"
  config  = { bucket = var.state_bucket, prefix = "10-network" }
}

data "terraform_remote_state" "gke" {
  backend = "gcs"
  config  = { bucket = var.state_bucket, prefix = "20-gke" }
}

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config  = { bucket = var.state_bucket, prefix = "30-iam" }
}

data "terraform_remote_state" "gateway" {
  backend = "gcs"
  config  = { bucket = var.state_bucket, prefix = "40-aigateway" }
}

data "terraform_remote_state" "ingress" {
  backend = "gcs"
  config  = { bucket = var.state_bucket, prefix = "50-ingress" }
}

locals {
  net = data.terraform_remote_state.network.outputs
  gke = data.terraform_remote_state.gke.outputs
  iam = data.terraform_remote_state.iam.outputs
  gw  = data.terraform_remote_state.gateway.outputs
  ing = data.terraform_remote_state.ingress.outputs
}
