# Platform context: AIRS AI Gateway (for downstream `apps` projects)

> Copy this file into your `apps` repo (e.g. as `docs/PLATFORM.md`, or fold into that
> repo's `CLAUDE.md`). It tells Claude/engineers in `apps` what the base platform is,
> how to read its state, and how to build on it. It is a **context/reference** doc — it
> describes the *shape* of the platform, not any one deployment. **Concrete values
> (names, endpoints, IDs) come from reading the platform state, never from this file** —
> so new environments can be added upstream without changing this doc.

## What the platform is

A separate repo (`k8s-tf-examples`) provisions, with staged Terraform, the **PRISMA AIRS
AI Gateway** (Portkey hybrid data-plane) on managed Kubernetes. It's the shared base your
`apps` project builds on. It exists in parallel for three clouds — **GKE** (→ Vertex AI),
**AKS** (→ Azure AI Foundry), **EKS** (→ Amazon Bedrock) — each structurally identical.

Per cloud, the stages are: `00-bootstrap` (remote-state backend) → `10-network` →
`20-<cluster>` → `30-iam` (pod identity + model access) → `40-aigateway` (the gateway Helm
release) → `50-ingress` (WAF + HTTPS LB) → **`90-platform`** (the output contract you
consume). A gateway pod proxies LLM requests to that cloud's model service using
**pod-level cloud identity** (Workload Identity / IRSA — no static keys), fronted by a
**WAF-protected HTTPS load balancer**.

## The golden rules for `apps`

1. **Read only the `90-platform` contract** via `terraform_remote_state` — never the
   internal stage states, and never modify platform resources. The platform may refactor
   internal stages; `90-platform` outputs are a stable, **additive-only** API.
2. **Keep your own state in the SAME backend, under `apps/<project>` keys** — never collide
   with the platform's numbered keys or `90-platform`. Locking is shared automatically.
3. **Call models through the gateway**, not directly at Foundry/Vertex/Bedrock — the gateway
   is the guardrail/policy/observability layer (that's the whole point of AIRS).
4. **Bring your own cloud auth** for talking to the cluster; the contract gives you the
   endpoint/CA + names, not tokens.
5. **Secrets never go in git or in the platform contract.** The platform's own secrets
   (Portkey key, model keys, any Datadog key) are NOT exposed to you; use your own secret
   store.

## How to read the state

You need two things from whoever runs the platform (or from the platform repo's
`terraform.tfvars` / `00-bootstrap` outputs): **which cloud** the target deployment is, and
the **backend coordinates** of its state store. Everything else you discover by reading the
`90-platform` outputs — so this doc stays valid as deployments change.

The backend type is cloud-specific; the pattern is the same (your own key next to the
platform's `90-platform` key, in the same store):

| Cloud | Backend | Your state key | Contract state key |
| --- | --- | --- | --- |
| GKE | `gcs` (bucket) | `prefix = "apps/<project>"` | `prefix = "90-platform"` |
| AKS | `azurerm` (Storage Account + container) | `key = "apps/<project>.tfstate"` | `key = "90-platform.tfstate"` |
| EKS | `s3` (bucket + DynamoDB lock) | `key = "apps/<project>.tfstate"` | `key = "90-platform.tfstate"` |

Wiring (AKS shown; swap the backend/data block for GKE `gcs` or EKS `s3` — see
[examples/consumer/](.)):

```hcl
terraform {
  # YOUR state — same store as the platform, your own key namespace.
  backend "azurerm" {
    resource_group_name  = "<state-rg>"
    storage_account_name = "<state-account>"
    container_name       = "<container>"
    key                  = "apps/myapp.tfstate"
  }
}

# Read the platform's published contract (never the internal stage states).
data "terraform_remote_state" "platform" {
  backend = "azurerm"
  config = {
    resource_group_name  = "<state-rg>"
    storage_account_name = "<state-account>"
    container_name       = "<container>"
    key                  = "90-platform.tfstate"
  }
}

locals { p = data.terraform_remote_state.platform.outputs }
```

Your identity needs **read** on the state store (for `90-platform`) and read/write on your
own `apps/*` key.

## The contract outputs (discover, don't assume)

Read the live set rather than trusting a copied list — it may grow over time and differs
per cloud. From the platform repo:

```sh
terraform -chdir=<CLOUD>/terraform/90-platform output        # human-readable
terraform -chdir=<CLOUD>/terraform/90-platform output -json  # machine-readable
```

`local.p.cloud` tells you which cloud you're on (`gke` / `aks` / `eks`), so you can branch.
The contract is designed to carry, across all clouds, a **common core** plus
**cloud-specific identity/model** fields:

- **Common core** — `cloud`, region/location, cluster name + API host + CA cert (sensitive),
  the cluster **OIDC issuer**, network IDs (VPC/VNet + subnets), the gateway's
  namespace/service/port (and MCP port), the external `gateway_url` / ingress IP / `mcp_url`,
  the WAF/policy name, and `model_backend`.
- **Cloud-specific** — the pod-identity handle and the model endpoint. GKE exposes the
  workload-identity pool, the gateway GSA, and the Vertex project/region. AKS exposes the
  gateway managed-identity client ID and the Foundry endpoint/account. EKS exposes the OIDC
  provider ARN/URL, the gateway role ARN, and the Bedrock/region details.

Use `local.p.<name>`; if an output you expect isn't present, you're probably pointed at a
different cloud — branch on `local.p.cloud`.

## How to build on it

**Call the gateway.** From outside the cluster, POST to `${local.p.gateway_url}/v1/...`
with Portkey headers (`x-portkey-api-key`, `x-portkey-provider`) — your caller's egress IP
must be in the gateway's WAF allowlist, and default certs are self-signed (`curl -k` / trust
it). In-cluster, hit
`http://${local.p.gateway_service}.${local.p.gateway_namespace}.svc:${local.p.gateway_service_port}`
(no WAF, no TLS). Models are addressed by the Portkey provider + deployment/model name,
never by calling the cloud model service directly.

**Deploy your own workloads to the cluster.** Configure the kubernetes/helm providers from
the contract's cluster host + CA cert **plus your own token** (mint it with your cloud CLI /
the cloud's cluster-auth data source — the platform repo's `40`/`50` stages show the
pattern). Put workloads in your **own namespace**, not the gateway's.

**Give your pods cloud identity (keyless).** Federate your own identity to the cluster's
OIDC issuer (from the contract) with subject
`system:serviceaccount:<your-ns>:<your-ksa>`, then wire the KSA per cloud (GKE: GSA
annotation; AKS: `azure.workload.identity/client-id` annotation + pod label; EKS: IRSA
role-arn annotation). Mirror the platform's `30-iam` stage.

**Network.** Place resources that must reach the cluster privately in the VPC/VNet +
subnets from the contract.

## Gotchas the platform already hit (so you don't repeat them)

- **Egress IP allowlisting**: the cluster API and the gateway WAF are locked to CIDR
  allowlists. New egress sources (CI, new NAT) must be added, or you get connection
  timeouts / `403`.
- **Model endpoint hostnames** can be finicky (e.g. Azure Foundry requires the
  custom-subdomain host, not the resource-name host). Take the endpoint from the contract.
- **Gateway SSRF guard** blocks loopback/private hosts unless allowlisted via
  `TRUSTED_CUSTOM_HOSTS` (only relevant if you add in-pod sidecars the gateway pushes to).
- **Model auth** is pod identity (Workload Identity / IRSA), configured in the Portkey
  control plane — not a static key.

## Stability & security

- Treat `90-platform` outputs as a versioned API; pin a **git tag** of the platform repo if
  you need change control. Expect additive-only changes.
- `terraform_remote_state` exposes the **entire** `90-platform` state, including sensitive
  outputs (cluster CA). Only trusted consumers should have state-read; don't echo those.
