# Consuming the platform from a downstream project

This platform publishes a **stable output contract** from the `90-platform` stage.
Downstream repos build on it by:

1. **Reading** the platform's `90-platform` state via `terraform_remote_state`.
2. **Storing their own state** in the **same backend** (bucket / Storage Account /
   lock table) under a **reserved key namespace** so it never collides with the
   platform's own state.

Key namespace convention — platform owns the numbered stage keys + `90-platform`;
consumers use `apps/<project>/…`:

| Cloud | Platform keys | Consumer keys |
|---|---|---|
| GKE (gcs `prefix`) | `00-bootstrap` … `50-ingress`, `90-platform` | `apps/<project>` |
| AKS (azurerm `key`) | `10-network.tfstate` … `90-platform.tfstate` | `apps/<project>.tfstate` |
| EKS (s3 `key`) | `10-network.tfstate` … `90-platform.tfstate` | `apps/<project>.tfstate` |

Locking is shared automatically across all keys (DynamoDB table / blob lease / GCS).

## Wiring (per cloud)

Copy [`main.tf.example`](main.tf.example) (it's AKS/azurerm; swap the `backend` and
`data` blocks for your cloud using the snippets below), fill in the backend
identifiers, then `terraform init` + `apply` in your own repo.

### GKE (gcs)
```hcl
terraform { backend "gcs" { bucket = "<state-bucket>", prefix = "apps/myapp" } }
data "terraform_remote_state" "platform" {
  backend = "gcs"
  config  = { bucket = "<state-bucket>", prefix = "90-platform" }
}
```

### AKS (azurerm)
```hcl
terraform { backend "azurerm" {
  resource_group_name = "<state-rg>", storage_account_name = "<account>",
  container_name = "tfstate", key = "apps/myapp.tfstate" } }
data "terraform_remote_state" "platform" {
  backend = "azurerm"
  config = { resource_group_name = "<state-rg>", storage_account_name = "<account>",
             container_name = "tfstate", key = "90-platform.tfstate" }
}
```

### EKS (s3)
```hcl
terraform { backend "s3" {
  bucket = "<state-bucket>", key = "apps/myapp.tfstate",
  region = "<region>", dynamodb_table = "<lock-table>" } }
data "terraform_remote_state" "platform" {
  backend = "s3"
  config = { bucket = "<state-bucket>", key = "90-platform.tfstate",
             region = "<region>", dynamodb_table = "<lock-table>" }
}
```

## Using the outputs

```hcl
locals { p = data.terraform_remote_state.platform.outputs }

# e.g. cluster + model service identifiers
#   local.p.cluster_name / cluster_endpoint / oidc_* / workload_pool
#   local.p.gateway_url / gateway_namespace / gateway_service
#   local.p.model_backend  (vertex-ai | azure-foundry | bedrock)
#   AKS: local.p.foundry_endpoint   GKE: local.p.vertex_project_id   EKS: local.p.oidc_provider_arn
```

To talk to the **cluster** from a consumer, configure the kubernetes/helm providers
with the platform's endpoint/CA outputs **plus your own cloud auth** (don't rely on
the platform for a bearer token):
- GKE: `google_client_config` token + `cluster_endpoint`/`cluster_ca_certificate`
- AKS: `az` / client cert, `cluster_host`/`cluster_ca_certificate`
- EKS: `aws_eks_cluster_auth` token + `cluster_endpoint`/`cluster_ca_certificate`

## Access & security

- The consumer's identity needs **read** on the state bucket/account (to read
  `90-platform`), and **read/write** on its own `apps/<project>` key.
- `terraform_remote_state` exposes the **entire** `90-platform` state, including any
  sensitive outputs (cluster CA, etc.). Grant state-bucket read only to trusted
  consumers; if you need tighter isolation, publish the needed values to a parameter
  store instead and read those.
- Treat the `90-platform` outputs as a versioned contract: **additive changes only**,
  and pin to a git tag of this repo if you want change control.
