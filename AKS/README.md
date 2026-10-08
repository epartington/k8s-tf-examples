# POV: AKS + PRISMA AIRS / Portkey AI Gateway (Terraform)

> **Status: implemented and deployed.** This mirrors the completed [GKE](../GKE/) project for
> **Azure AKS**. All six stages are written, `terraform validate`-clean, and have been
> **applied end-to-end against a live subscription** (POV): private cluster, gateway, and
> WAF-protected App Gateway up, with keyless Workload Identity to Azure AI Foundry verified. See
> [terraform/README.md](terraform/README.md) for the apply loop, prerequisites, and the
> per-stage READMEs; the GKE→Azure mapping below captures the design.

The goal matches GKE: a repeatable, POV-scale project that stands up an **isolated VNet**
in an **existing** Azure subscription and deploys the **PRISMA AIRS AI Gateway** (Portkey
hybrid data-plane) on a small **private AKS cluster**, so the gateway can proxy requests to
**Azure AI Foundry** models via **Workload Identity** (AAD federation, no static keys).

Inbound traffic reaches the gateway through a **public HTTPS load balancer** locked down by
a **WAF** (IP allowlist). Same MCP story as GKE: the gateway (8787) and MCP server (8788)
run in one pod and are fronted by the same LB/cert/WAF.

## Layout — apply in numeric order

```text
AKS/terraform/
  00-bootstrap/   # Resource group + Storage Account/container for TF state (azurerm backend); register providers
  10-network/     # VNet, subnet, NAT Gateway, NSG, public IP
  20-aks/         # Private AKS cluster + node pool, OIDC issuer + Workload Identity
  30-iam/         # gateway + AGIC managed identities (federated) + Azure AI Foundry account + role
  40-aigateway/     # namespace + helm_release of airs-gw (console values.yaml + Azure overlay)
  50-ingress/     # WAF policy, Key Vault self-signed cert, App Gateway (WAF_v2) + AGIC + Ingress
```

## GKE → Azure mapping

| Concern              | GKE                                   | AKS                                                                  |
|----------------------|---------------------------------------|---------------------------------------------------------------------|
| TF state backend     | GCS bucket (`gcs`)                     | Storage Account + blob container (`azurerm`)                         |
| Isolated network     | VPC + subnet                          | VNet + subnets (aks + appgw)                                         |
| Egress               | Cloud NAT                             | NAT Gateway                                                          |
| Firewall             | VPC firewall rules                    | Network Security Group (NSG)                                         |
| Private cluster      | private nodes, authorized networks    | private AKS, API server authorized IP ranges                        |
| Pod-level cloud auth | Workload Identity (GSA↔KSA)           | Entra Workload Identity (managed identity ↔ KSA via OIDC federation) |
| Model backend        | Vertex AI (`roles/aiplatform.user`)   | Azure AI Foundry — AIServices account (`Cognitive Services User` role) |
| Gateway auth mode    | `GCP_AUTH_MODE=workload`              | workload-identity SA annotation + pod label (API-key fallback)      |
| Static ingress IP    | global static IP                      | Standard public IP                                                   |
| L7 inbound + WAF     | Global external ALB + Cloud Armor     | Application Gateway v2 + AGIC + WAF policy                           |
| Managed TLS          | Google-managed cert                   | self-signed Key Vault cert (swap in a real cert)                     |

## Reuse from GKE

Stage **40-aigateway** is almost cloud-agnostic: same official Helm repo
(`https://portkey-ai.github.io/airs-gw-helm`), same console-downloaded `values.yaml` for
credentials, same overlay pattern. Only the cloud-specific overlay changes (Workload
Identity annotations and auth-mode env) — see the GKE
[40-aigateway](../GKE/terraform/40-aigateway/) stage as the reference implementation.
