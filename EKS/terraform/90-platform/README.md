# 90-platform — published output contract for downstream projects

A **read-only aggregation stage**. It reads every other stage's remote state and
re-exports a single, curated, **stable output set** into its own state (key
`90-platform.tfstate`). Downstream (consumer) repos read **only this** state via
`terraform_remote_state` — they never depend on the internal stage layout, so you can
refactor stages without breaking consumers, as long as these outputs stay stable.

Creates **no infrastructure** — just outputs. Apply it last, after `50-ingress`.

## Reads

`10-network`, `20-eks`, `30-iam`, `40-aigateway`, `50-ingress` (via `terraform_remote_state`).

## Inputs used (from `../terraform.tfvars`)

`region`, `state_bucket`, `state_lock_table`.

## Run

```sh
cd 90-platform
terraform init \
  -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)" \
  -backend-config="dynamodb_table=$(terraform -chdir=../00-bootstrap output -raw state_lock_table)" \
  -backend-config="region=$(terraform -chdir=../00-bootstrap output -raw region)"
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs (the contract — additive changes only)

`cloud`, `region`, `cluster_name`, `cluster_endpoint`, `cluster_ca_certificate`,
`oidc_provider_arn`, `oidc_provider_url`, `vpc_id`, `private_subnet_ids`,
`public_subnet_ids`, `gateway_namespace`, `gateway_service`, `gateway_service_port`,
`mcp_enabled`, `mcp_service_port`, `gateway_role_arn`, `lb_controller_role_arn`,
`model_backend`, `alb_hostname`, `gateway_domain`, `gateway_url`, `mcp_domain`,
`mcp_url`, `waf_web_acl_arn`.

## Consuming it from another project

A downstream repo keeps its **own** state in the **same S3 bucket** (and lock table)
under a reserved key prefix, and reads this contract:

```hcl
# downstream backend — same bucket/lock table, your own key (never collides)
terraform {
  backend "s3" {
    bucket         = "<same-state-bucket>"
    key            = "apps/myapp.tfstate"
    region         = "<region>"
    dynamodb_table = "<same-lock-table>"
  }
}

# read the platform contract
data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket         = "<same-state-bucket>"
    key            = "90-platform.tfstate"
    region         = "<region>"
    dynamodb_table = "<same-lock-table>"
  }
}

# use it, e.g. data.terraform_remote_state.platform.outputs.oidc_provider_arn
```

The consumer's identity needs **read** access to the state bucket. Reading remote
state exposes the whole state file (incl. sensitive attributes), so scope that access
accordingly. See [../README.md](../README.md#consuming-this-platform) and
[examples/consumer](../../../examples/consumer/).
