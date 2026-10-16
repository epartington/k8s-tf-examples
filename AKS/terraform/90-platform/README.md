# 90-platform — published output contract for downstream projects

A **read-only aggregation stage**. It reads every other stage's remote state and
re-exports a single, curated, **stable output set** into its own state (key
`90-platform.tfstate`). Downstream (consumer) repos read **only this** state via
`terraform_remote_state` — they never depend on the internal stage layout, so you can
refactor stages without breaking consumers, as long as these outputs stay stable.

Creates **no infrastructure** — just outputs. Apply it last, after `50-ingress`.

## Reads

`10-network`, `20-aks`, `30-iam`, `40-aigateway`, `50-ingress` (via `terraform_remote_state`).

## Inputs used (from `../terraform.tfvars`)

`state_resource_group`, `storage_account`, `container_name`.

## Run

```sh
cd 90-platform
terraform init \
  -backend-config="resource_group_name=$(terraform -chdir=../00-bootstrap output -raw resource_group_name)" \
  -backend-config="storage_account_name=$(terraform -chdir=../00-bootstrap output -raw storage_account_name)"
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs (the contract — additive changes only)

`cloud`, `location`, `resource_group_name`, `cluster_name`, `node_resource_group`,
`cluster_host` (sensitive), `cluster_ca_certificate` (sensitive), `oidc_issuer_url`,
`vnet_id`, `aks_subnet_id`, `appgw_subnet_id`, `gateway_namespace`, `gateway_service`,
`gateway_service_port`, `mcp_enabled`, `mcp_service_port`, `gateway_identity_client_id`,
`model_backend`, `foundry_account_id`, `foundry_endpoint`, `foundry_deployment_name`,
`ingress_ip`, `gateway_domain`, `gateway_url`, `mcp_domain`, `mcp_url`, `waf_policy_name`.

## Consuming it from another project

A downstream repo keeps its **own** state in the **same Storage Account/container**
under a reserved key prefix, and reads this contract:

```hcl
# downstream backend — same account/container, your own key (never collides)
terraform {
  backend "azurerm" {
    resource_group_name  = "<state-resource-group>"
    storage_account_name = "<same-storage-account>"
    container_name       = "tfstate"
    key                  = "apps/myapp.tfstate"
  }
}

# read the platform contract
data "terraform_remote_state" "platform" {
  backend = "azurerm"
  config = {
    resource_group_name  = "<state-resource-group>"
    storage_account_name = "<same-storage-account>"
    container_name       = "tfstate"
    key                  = "90-platform.tfstate"
  }
}

# use it, e.g. data.terraform_remote_state.platform.outputs.foundry_endpoint
```

The consumer's identity needs **read** access to the state Storage Account. Reading
remote state exposes the whole state file (incl. sensitive attributes), so scope that
access accordingly. See [../README.md](../README.md#consuming-this-platform) and
[examples/consumer](../../../examples/consumer/).
