# POV: AKS + PRISMA AIRS / Portkey AI Gateway (Terraform)

> **Status: scaffold / planned.** This mirrors the completed [GKE](../GKE/) project for
> **Azure AKS**. The staged directory layout is in place; the Terraform for each stage is
> not written yet. This README captures the intended architecture and the GKE→Azure
> mapping so the stages can be filled in consistently.

The goal matches GKE: a repeatable, POV-scale project that stands up an **isolated VNet**
in an **existing** Azure subscription and deploys the **PRISMA AIRS AI Gateway** (Portkey
hybrid data-plane) on a small **private AKS cluster**, so the gateway can proxy requests to
**Azure OpenAI** models via **Workload Identity** (AAD federation, no static keys).

Inbound traffic reaches the gateway through a **public HTTPS load balancer** locked down by
a **WAF** (IP allowlist). Same MCP story as GKE: the gateway (8787) and MCP server (8788)
run in one pod and are fronted by the same LB/cert/WAF.

## Layout — apply in numeric order

```text
AKS/terraform/
  00-bootstrap/   # Resource group + Storage Account/container for TF state (azurerm backend); register providers
  10-network/     # VNet, subnet, NAT Gateway, NSG, public IP
  20-aks/         # Private AKS cluster + node pool, OIDC issuer + Workload Identity
  30-iam/         # User-assigned managed identity + federated credential + role assignment (Azure OpenAI)
  40-portkey/     # namespace + helm_release of airs-gw (console values.yaml + Azure overlay)
  50-ingress/     # WAF policy, TLS cert, ingress (Application Gateway/AGIC or Front Door)
```

## GKE → Azure mapping

| Concern              | GKE                                   | AKS (planned)                                                        |
|----------------------|---------------------------------------|---------------------------------------------------------------------|
| TF state backend     | GCS bucket (`gcs`)                     | Storage Account + blob container (`azurerm`)                         |
| Isolated network     | VPC + subnet                          | VNet + subnet                                                        |
| Egress               | Cloud NAT                             | NAT Gateway                                                          |
| Firewall             | VPC firewall rules                    | Network Security Group (NSG)                                         |
| Private cluster      | private nodes, authorized networks    | private AKS, API server authorized IP ranges                        |
| Pod-level cloud auth | Workload Identity (GSA↔KSA)           | AKS Workload Identity (managed identity ↔ KSA via OIDC federation)   |
| Model backend        | Vertex AI (`roles/aiplatform.user`)   | Azure OpenAI (`Cognitive Services OpenAI User` role assignment)      |
| Gateway auth mode    | `GCP_AUTH_MODE=workload`              | Azure workload identity env (per chart Azure docs)                  |
| Static ingress IP    | global static IP                      | Standard public IP                                                   |
| L7 inbound + WAF     | Global external ALB + Cloud Armor     | Application Gateway + AGIC + WAF policy (or Front Door + WAF)        |
| Managed TLS          | Google-managed cert                   | App Gateway cert / Key Vault cert / managed cert                     |

## Reuse from GKE

Stage **40-portkey** is almost cloud-agnostic: same official Helm repo
(`https://portkey-ai.github.io/airs-gw-helm`), same console-downloaded `values.yaml` for
credentials, same overlay pattern. Only the cloud-specific overlay changes (Workload
Identity annotations and auth-mode env) — see the GKE
[40-portkey](../GKE/terraform/40-portkey/) stage as the reference implementation.
