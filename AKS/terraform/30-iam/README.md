# 30-iam — Workload Identity + Azure OpenAI

Creates the managed identities the gateway pod and AGIC run as, federates them to
their Kubernetes service accounts via the cluster OIDC issuer, and (optionally)
creates the Azure OpenAI account + model deployment the gateway proxies to. State
key `30-iam.tfstate`. Fast (a few seconds; the OpenAI deployment adds a minute).

## Creates

- `azurerm_user_assigned_identity.gateway` + `azurerm_federated_identity_credential.gateway`
  — the gateway pod identity, federated to `system:serviceaccount:<namespace>:<ksa_name>`.
- `azurerm_cognitive_account.openai` + `azurerm_cognitive_deployment.model`
  (when `create_openai = true`) — the Azure OpenAI account + one model deployment.
- `azurerm_role_assignment.openai_user` — **`Cognitive Services OpenAI User`** for
  the gateway identity on the OpenAI account (mirrors `roles/aiplatform.user`).
- `azurerm_user_assigned_identity.agic` + federated credential + a `Contributor`
  role assignment on the workload RG — the identity the stage-50 Helm AGIC uses to
  manage the Application Gateway.

## Reads

- `10-network` — `resource_group_name`, `resource_group_id`, `location`.
- `20-aks` — `oidc_issuer_url` for the federated credentials.

## Inputs used (from `../terraform.tfvars`)

`subscription_id`, `state_resource_group`, `storage_account`, `namespace`,
`ksa_name` (**must match stage 40**), `create_openai`, `openai_account_name`,
`openai_deployment_name`, `openai_model_name`, `openai_model_version` (optional),
`openai_capacity`, `openai_location` (optional), or `openai_account_id` when
`create_openai = false`.

## Run

```sh
cd 30-iam
terraform init \
  -backend-config="resource_group_name=$(terraform -chdir=../00-bootstrap output -raw resource_group_name)" \
  -backend-config="storage_account_name=$(terraform -chdir=../00-bootstrap output -raw storage_account_name)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`gateway_identity_client_id` (KSA annotation in stage 40), `gateway_identity_id`,
`gateway_identity_principal_id`, `namespace`, `ksa_name`, `agic_identity_client_id`,
`agic_namespace`, `agic_ksa_name`, `openai_account_id`, `openai_endpoint`,
`openai_deployment_name`.

## Notes

- `namespace`/`ksa_name` here **must** equal the same vars in stage 40, or the
  federated credential won't match the KSA the chart creates and Azure OpenAI
  calls will fail with authorization errors.
- The AGIC identity is federated to `agic_namespace`/`agic_ksa_name` — these must
  match the namespace and service-account name the AGIC Helm chart uses in stage 50
  (defaults `default` / `ingress-azure`).
- `Contributor` on the workload RG is POV-scoped; tighten it to the App Gateway
  resource for production.
- Model availability is region-specific. `openai_location` (or the network region)
  must be a region where `openai_model_name` is offered.
