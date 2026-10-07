# 30-iam — Workload Identity + Azure AI Foundry

Creates the managed identities the gateway pod and AGIC run as, federates them to
their Kubernetes service accounts via the cluster OIDC issuer, and (optionally)
creates the Azure AI Foundry account + model deployment the gateway proxies to.
State key `30-iam.tfstate`. Fast (a few seconds; the deployment adds a minute).

## Creates

- `azurerm_user_assigned_identity.gateway` + `azurerm_federated_identity_credential.gateway`
  — the gateway pod identity, federated to `system:serviceaccount:<namespace>:<ksa_name>`.
- `azurerm_cognitive_account.foundry` (**`kind = "AIServices"`**) +
  `azurerm_cognitive_deployment.model` (when `create_foundry = true`) — the Azure AI
  Foundry account and one model deployment. AIServices is a single endpoint serving
  the full Foundry catalog (OpenAI + Llama, Mistral, Phi, DeepSeek, …), the Azure
  analog of Vertex Model Garden / Bedrock foundation models.
- `azurerm_role_assignment.model_access` — `for_each` over `model_access_roles`
  (default **`Cognitive Services User`** + **`Cognitive Services OpenAI User`**) for
  the gateway identity on the Foundry account, keyless via Entra (mirrors
  `roles/aiplatform.user` / `bedrock:InvokeModel`).
- `azurerm_user_assigned_identity.agic` + federated credential + a `Contributor`
  role assignment on the workload RG — the identity the stage-50 Helm AGIC uses to
  manage the Application Gateway.

## Reads

- `10-network` — `resource_group_name`, `resource_group_id`, `location`.
- `20-aks` — `oidc_issuer_url` for the federated credentials.

## Inputs used (from `../terraform.tfvars`)

`subscription_id`, `state_resource_group`, `storage_account`, `namespace`,
`ksa_name` (**must match stage 40**), `create_foundry`, `foundry_account_name`,
`foundry_deployment_name`, `foundry_model_format`, `foundry_model_name`,
`foundry_model_version` (optional), `foundry_capacity`, `foundry_location`
(optional), `model_access_roles`, or `foundry_account_id` when
`create_foundry = false`.

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
`agic_namespace`, `agic_ksa_name`, `foundry_account_id`, `foundry_endpoint`,
`foundry_deployment_name`.

## Notes

- `namespace`/`ksa_name` here **must** equal the same vars in stage 40, or the
  federated credential won't match the KSA the chart creates and Foundry model
  calls will fail with authorization errors.
- The AGIC identity is federated to `agic_namespace`/`agic_ksa_name` — these must
  match the namespace and service-account name the AGIC Helm chart uses in stage 50
  (defaults `default` / `ingress-azure`).
- `Contributor` on the workload RG is POV-scoped; tighten it to the App Gateway
  resource for production.
- Model availability is region-specific. `foundry_location` (or the network region)
  must be a region where `foundry_model_name` is offered. Set `foundry_model_format`
  to the model's publisher (`OpenAI`, `Meta`, `Mistral AI`, `DeepSeek`, …) when
  deploying non-OpenAI catalog models.

## Using an existing / separate Foundry

If you already run an Azure AI Foundry (**AIServices** account) — e.g. a central AI
team's — don't create a new one. Point this stage at it instead:

```hcl
create_foundry     = false
foundry_account_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<foundry-name>"
foundry_endpoint   = "https://<foundry-name>.services.ai.azure.com/"  # surfaced via the foundry_endpoint output
# foundry_deployment_name = "<existing-deployment>"                   # a model already deployed there
```

What happens:

- **Nothing about the pod identity changes.** The gateway still authenticates via
  Workload Identity → the UAMI. Only the **role-assignment scope** changes.
- `azurerm_role_assignment.model_access` grants the gateway UAMI the
  `model_access_roles` (`Cognitive Services User` + `Cognitive Services OpenAI User`)
  **on the existing account's resource ID** — keyless Entra access to its models. No
  new account or deployment is created.
- **Use the AIServices account ID as the scope.** Model deployments and the inference
  endpoint live at the account; **projects under it inherit account-level data-plane
  access**, so you don't scope per project.

Requirements / caveats:

- **Operator rights on that scope.** `terraform apply` creates a role assignment on
  the existing account, so the identity running Terraform needs **User Access
  Administrator or Owner** on that account (or its RG). This works across a different
  resource group or **subscription** as long as it's the **same Entra tenant**; it
  does **not** work cross-tenant.
- **Same-tenant only for keyless.** If the Foundry is in another tenant, or the owning
  team won't grant RBAC, fall back to an **API key**: put it in the console
  `values.yaml` (ideally Key Vault / CSI) and configure the `azure-ai` provider in the
  Portkey console with the key. You lose Workload Identity but it crosses any boundary.
- **Portkey config.** Point the `azure-ai` provider at `foundry_endpoint` and the
  deployment names that already exist in that Foundry — this stage doesn't manage them.
