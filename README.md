# k8s-tf-examples

Repeatable, POV-scale Terraform for deploying the **PRISMA AIRS AI Gateway** (Portkey
hybrid data-plane) on managed Kubernetes across the major public clouds. Each provider is a
top-level directory with the same staged layout (`00-bootstrap` → `50-ingress`): isolated
network → private cluster → pod-level cloud IAM → gateway (Helm) → WAF-protected HTTPS
ingress. The gateway API (8787) and MCP server (8788) are both fronted by the same load
balancer, TLS cert, and WAF/IP allowlist.

- **[GKE](GKE/)** — Google Kubernetes Engine, model backend **Vertex AI**. ✅ Implemented (reference).
- **[AKS](AKS/)** — Azure Kubernetes Service, model backend **Azure OpenAI**. 🚧 Scaffold.
- **[EKS](EKS/)** — Amazon EKS, model backend **Amazon Bedrock**. 🚧 Scaffold.

Start with [GKE](GKE/terraform/README.md) — it is the reference implementation. The AKS and
EKS READMEs map each GKE stage to its Azure/AWS equivalent so they can be filled in
consistently. Stage `40-portkey` (the Helm release) is largely cloud-agnostic and reused
across all three.
