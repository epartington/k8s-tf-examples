# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## What this repo is

Repeatable, **POV-scale** Terraform for deploying the **PRISMA AIRS AI Gateway** (Portkey
hybrid data-plane) on managed Kubernetes across the major public clouds. Each cloud is a
top-level directory sharing the same **staged** layout; a gateway pod proxies LLM requests
to that cloud's model service using **pod-level cloud identity** (no static keys), fronted
by a **WAF-protected HTTPS load balancer**.

```text
k8s-tf-examples/
  GKE/   # Google Kubernetes Engine → Vertex AI        (✅ implemented, reference)
  AKS/   # Azure Kubernetes Service → Azure AI Foundry  (✅ implemented)
  EKS/   # Amazon EKS → Amazon Bedrock                  (✅ implemented)
```

Start from [GKE/terraform/README.md](GKE/terraform/README.md) — it is the reference
implementation. **AKS** and **EKS** are complete parallel implementations (all six stages,
validated; not yet applied end-to-end against a live subscription/account).

## Staged layout (every provider)

Terraform is split into ordered, independent root modules under `<CLOUD>/terraform/`. Apply
in numeric order; each later stage reads earlier outputs via `terraform_remote_state`.

| Stage          | Purpose |
|----------------|---------|
| `00-bootstrap` | Remote-state backend (bucket/account + lock) and enable/register cloud APIs. **Local state.** |
| `10-network`   | Isolated network: VPC/VNet, subnets, egress NAT, firewall/NSG/SG, static ingress IP. |
| `20-<k8s>`     | Private cluster + node pool, OIDC issuer for pod identity. |
| `30-iam`       | Cloud identity for the gateway pod (WI/IRSA) + model-service role binding. |
| `40-aigateway`   | Namespace + `helm_release` of `airs-gw` (mostly cloud-agnostic). |
| `50-ingress`   | WAF/IP allowlist, managed TLS cert, HTTPS load balancer / Ingress. |

Stage `00-bootstrap` uses **local** state to create the remote backend; stages `10`–`50`
use the remote backend with a per-stage `prefix`/`key`. The state bucket/account name is set
**once** in `terraform.tfvars` and passed to each stage at `init` via `-backend-config` — it
is never hardcoded in a `backend {}` block.

## How it is applied

- **Locally**, authenticated through the cloud CLI (GKE: `gcloud auth application-default
  login` for ADC — separate from `gcloud auth login`; AKS: `az login` + `az account set`).
  See the provider README for the exact apply loop and prerequisites.
- The machine running Terraform must be in the cluster's control-plane authorized-network
  allowlist (stages 40/50 talk to the cluster API), and in the WAF allowlist to call the
  gateway. Public egress IP: `curl -s ifconfig.me`.
- Gateway (`8787`) and MCP server (`8788`) run in one pod and are both fronted by the same
  load balancer, cert, and WAF — MCP host-based on `mcp.<domain>` (the L7 load balancers here
  don't strip path prefixes, so a dedicated host with `/*` is used rather than a `/mcp` path).

## Conventions & guardrails

- **Never commit secrets.** Credentials come from a `values.yaml` **downloaded from the AI
  Gateway console** and placed at `<CLOUD>/terraform/40-aigateway/values.yaml`. That file, all
  `*.tfvars` (except `*.tfvars.example`), and `*.tfstate*` are gitignored. Verify with
  `git check-ignore <path>` before adding anything under `40-aigateway/`.
- `40-aigateway` pulls the chart from the official Helm repo
  (`https://portkey-ai.github.io/airs-gw-helm`); a copy is vendored under
  `GKE/docs/airs-gw-helm-main/` **for reference only**. The **chart version is pinned**
  (`chart_version`, default `1.2.0`; set `""` for latest). Image tags come from the chart
  `appVersion` / console `values.yaml` unless overridden via `image_repository`/`image_tag`
  (gateway only) or the `image_overrides` map (any chart image, on top of the pinned chart).
- Terraform passes the console `values.yaml` first and a **Terraform-generated overlay**
  second, so the overlay wins on intersection (Workload Identity annotation/pod label, LB/NEG
  annotations, auth-mode env, `ingress.enabled=false`). Keep cloud-specific settings in the
  overlay, not the console file. The combined `helm_release` values are wrapped in
  `sensitive()` so credentials don't surface in `plan`/`apply` output.
- Run `terraform fmt` and `terraform validate` before proposing changes. Validate needs
  `terraform init -backend=false` first; `40-aigateway` also needs a real `values.yaml` present
  (it uses `file()`), so it can't be validated without one.
- Keep the three providers structurally parallel: same stage numbers (00-bootstrap →
  50-ingress) and the same console-values + overlay pattern. All three (GKE, AKS, EKS)
  are now complete parallels — when changing one, apply the equivalent change to the
  others (or document why it doesn't map, e.g. AWS WAF needs no CIDR chunking, EKS node
  identity is minimal by default), and follow each provider README's GKE→cloud mapping.

## Working agreements

- Commit or push **only when the user explicitly asks.** This environment has no Git
  credentials, so pushes must come from the user's side.
- Before editing or deleting a file, read it — especially anything under `40-aigateway/`, which
  may contain live credentials that must not be echoed or committed.
