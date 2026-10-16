# 90-platform — published output contract for downstream projects

A **read-only aggregation stage**. It reads every other stage's remote state and
re-exports a single, curated, **stable output set** into its own state (prefix
`90-platform`). Downstream (consumer) repos read **only this** state via
`terraform_remote_state` — they never depend on the internal stage layout, so you
can refactor stages (e.g. rename `40-aigateway`) without breaking consumers, as long
as these outputs stay stable.

Creates **no infrastructure** — just outputs. Apply it last, after `50-ingress`.

## Reads

`10-network`, `20-gke`, `30-iam`, `40-aigateway`, `50-ingress` (via `terraform_remote_state`).

## Inputs used (from `../terraform.tfvars`)

`state_bucket`.

## Run

```sh
cd 90-platform
terraform init -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)"
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs (the contract — additive changes only)

`cloud`, `location`, `cluster_name`, `cluster_endpoint` (sensitive),
`cluster_ca_certificate` (sensitive), `workload_pool`, `network_self_link`,
`subnet_self_link`, `static_ip_address`, `gateway_namespace`, `gateway_service`,
`gateway_service_port`, `mcp_enabled`, `mcp_service_port`, `gateway_gsa_email`,
`model_backend`, `vertex_project_id`, `vertex_region`, `ingress_ip`,
`gateway_domain`, `gateway_url`, `mcp_domain`, `mcp_url`, `security_policy_name`.

## Consuming it from another project

A downstream repo keeps its **own** state in the **same bucket** under a reserved
key prefix, and reads this contract:

```hcl
# downstream backend — same bucket, your own prefix (never collides with platform)
terraform {
  backend "gcs" {
    bucket = "<same-state-bucket>"
    prefix = "apps/myapp"
  }
}

# read the platform contract
data "terraform_remote_state" "platform" {
  backend = "gcs"
  config  = { bucket = "<same-state-bucket>", prefix = "90-platform" }
}

# use it
# data.terraform_remote_state.platform.outputs.cluster_endpoint
# data.terraform_remote_state.platform.outputs.workload_pool
```

The consumer's identity needs **read** access to the state bucket. Note that reading
remote state exposes the whole state file (including sensitive attributes), so scope
that access accordingly. See [../README.md](../README.md#consuming-this-platform)
and [examples/consumer](../../../examples/consumer/).
