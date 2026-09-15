# POV: EKS + PRISMA AIRS / Portkey AI Gateway (Terraform)

> **Status: scaffold / planned.** This mirrors the completed [GKE](../GKE/) project for
> **AWS EKS**. The staged directory layout is in place; the Terraform for each stage is not
> written yet. This README captures the intended architecture and the GKE→AWS mapping so
> the stages can be filled in consistently.

The goal matches GKE: a repeatable, POV-scale project that stands up an **isolated VPC** in
an **existing** AWS account and deploys the **PRISMA AIRS AI Gateway** (Portkey hybrid
data-plane) on a small **private EKS cluster**, so the gateway can proxy requests to
**Amazon Bedrock** models via **IRSA** (IAM Roles for Service Accounts, no static keys).

Inbound traffic reaches the gateway through a **public HTTPS load balancer** locked down by
**AWS WAF** (IP allowlist). Same MCP story as GKE: the gateway (8787) and MCP server (8788)
run in one pod and are fronted by the same LB/cert/WAF.

## Layout — apply in numeric order

```text
EKS/terraform/
  00-bootstrap/   # S3 bucket + DynamoDB lock table for TF state (s3 backend)
  10-network/     # VPC, public/private subnets, IGW, NAT Gateway, security groups, EIP
  20-eks/         # Private EKS cluster + managed node group, OIDC provider (IRSA)
  30-iam/         # IAM role for service account (IRSA) + policy (Amazon Bedrock)
  40-portkey/     # namespace + helm_release of airs-gw (console values.yaml + AWS overlay)
  50-ingress/     # WAF web ACL, ACM cert, ingress (ALB via AWS Load Balancer Controller)
```

## GKE → AWS mapping

| Concern              | GKE                                   | EKS (planned)                                                       |
|----------------------|---------------------------------------|--------------------------------------------------------------------|
| TF state backend     | GCS bucket (`gcs`)                    | S3 bucket + DynamoDB lock table (`s3`)                              |
| Isolated network     | VPC + subnet                          | VPC + public/private subnets                                       |
| Egress               | Cloud NAT                             | NAT Gateway                                                         |
| Firewall             | VPC firewall rules                    | Security groups + NACLs                                             |
| Private cluster      | private nodes, authorized networks    | private EKS, `endpointPublicAccess` CIDR allowlist                 |
| Pod-level cloud auth | Workload Identity (GSA↔KSA)           | IRSA (IAM role ↔ KSA via cluster OIDC provider)                    |
| Model backend        | Vertex AI (`roles/aiplatform.user`)   | Amazon Bedrock (`bedrock:InvokeModel*` IAM policy)                 |
| Gateway auth mode    | `GCP_AUTH_MODE=workload`             | AWS default credential chain via IRSA (per chart Bedrock docs)     |
| Static ingress IP    | global static IP                      | ALB (DNS name; EIP for NLB if needed)                             |
| L7 inbound + WAF     | Global external ALB + Cloud Armor     | ALB (AWS Load Balancer Controller) + AWS WAF web ACL              |
| Managed TLS          | Google-managed cert                   | ACM certificate                                                    |

## Reuse from GKE

Stage **40-portkey** is almost cloud-agnostic: same official Helm repo
(`https://portkey-ai.github.io/airs-gw-helm`), same console-downloaded `values.yaml` for
credentials, same overlay pattern. Only the cloud-specific overlay changes (IRSA role-ARN
service-account annotation and auth env) — see the GKE
[40-portkey](../GKE/terraform/40-portkey/) stage as the reference implementation.
