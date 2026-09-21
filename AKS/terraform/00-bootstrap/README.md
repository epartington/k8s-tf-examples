# 00-bootstrap — remote-state backend + provider registration

First stage. Creates the resource group + Storage Account (blob container) that
every later stage uses for remote state, and registers the Azure resource
providers the project needs. **Uses LOCAL state** (it can't use the remote
backend — it's creating it).

## Creates

- `azurerm_resource_group.state` — resource group named `state_resource_group`.
- `azurerm_storage_account.tfstate` — versioned, TLS1.2 Storage Account named
  `storage_account`. Holds the remote state for stages 10–50 (one blob `key` each).
- `azurerm_storage_container.tfstate` — the `tfstate` container.
- `azurerm_resource_provider_registration.this` — registers
  `Microsoft.ContainerService`, `Microsoft.Network`, `Microsoft.CognitiveServices`,
  `Microsoft.ManagedIdentity`, `Microsoft.KeyVault` (skip with `register_providers = false`).

## Reads

Nothing — this is the root of the chain.

## Inputs used (from `../terraform.tfvars`)

`subscription_id`, `location`, `state_resource_group`, `storage_account`
(globally unique), `container_name`, `register_providers`. The state
resource-group + storage-account names must match what every later stage inits
against.

## Run

```sh
cd 00-bootstrap
terraform init                                   # local state, no backend config
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

The many "Value for undeclared variable" warnings are expected: the shared
`terraform.tfvars` carries inputs for all stages, and each stage ignores the ones
it doesn't declare.

## Outputs

- `resource_group_name` / `storage_account_name` — feed both to every later
  stage's `init` (the other READMEs use
  `terraform -chdir=../00-bootstrap output -raw <name>`).
- `container_name` — the blob container holding the per-stage state.

## Notes

- The Storage Account carries `prevent_destroy`. To tear the project down fully
  you must empty and remove it manually (see the top-level [README](../README.md#teardown)).
- Provider registration needs subscription-level rights. If they are already
  registered (or you lack rights), set `register_providers = false`.
