# POV: EKS + PRISMA AIRS / Portkey AI Gateway (Terraform)

A repeatable, POV-scale Terraform project that stands up an **isolated VPC** in an
**existing** AWS account and deploys the **PRISMA AIRS AI Gateway** (Portkey hybrid
data-plane) on a small **2-node private EKS cluster**, so the gateway can proxy
requests to **Amazon Bedrock** models via **IRSA** (IAM Roles for Service Accounts,
no static keys).

Inbound traffic reaches the gateway through a **public HTTPS ALB** locked down by an
**AWS WAFv2 web ACL** (IP allowlist, default-block). Both the **gateway API**
(port 8787) and the **MCP server** (port 8788) run in the same pod and are fronted
by that **same** ALB, cert, and WAF — the gateway on the primary domain and MCP on
an `mcp.<domain>` host.

This is the AWS port of the [GKE reference](../../GKE/terraform/README.md); it
preserves the same six numbered stages and the same console-`values.yaml` +
Terraform-overlay Helm pattern. See [../README.md](../README.md) for the GKE→AWS
mapping table.

## Architecture

- **Isolated VPC** with public + private subnets across two AZs; a VPC-integrated
  EKS cluster (private nodes, public API endpoint restricted to `authorized_networks`).
- **NAT Gateway** for egress (image pulls + reaching `api.portkey.ai` / `albus.portkey.ai`).
- **IRSA**: an IAM role with a Bedrock invoke policy, federated to the gateway KSA
  via the cluster OIDC provider — injected by the EKS pod-identity webhook, no static
  keys.
- **Hybrid deployment**: the data-plane runs in-cluster and syncs to the Portkey
  SaaS control plane (needs the console `values.yaml` credentials).
- **Bundled Redis** (cache); log/analytics stores set to `control_plane`.
- **MCP**: `server_mode = "all"` (default) runs the MCP server alongside the gateway
  on port 8788; stage 50 routes an `mcp.<domain>` host to it through the same ALB.

## Layout — apply in numeric order

```text
EKS/terraform/
  terraform.tfvars.example   # copy to terraform.tfvars and edit
  00-bootstrap/   # S3 state bucket + DynamoDB lock table (LOCAL state)
  10-network/     # VPC, public/private subnets (multi-AZ), IGW, NAT, routing
  20-eks/         # private EKS cluster + node group, OIDC provider, cluster/node IAM roles
  30-iam/         # gateway IRSA role (Bedrock) + AWS LB Controller IRSA role
  40-aigateway/   # namespace + helm_release of airs-gw (console values.yaml + AWS overlay)
  50-ingress/     # WAFv2 web ACL, ACM cert, AWS LB Controller (Helm), ALB Ingress
```

Each stage is an independent root module with its own `s3` backend state (except
`00-bootstrap`, local state). Later stages read earlier outputs via
`terraform_remote_state`. Each stage folder has its own README.

## Prerequisites

- An existing AWS account and the `aws` CLI authenticated with sufficient IAM
  (admin-ish for the POV: VPC/EKS/IAM/ELB/WAF/ACM/S3/DynamoDB).
- `terraform >= 1.5`, `kubectl`, `helm`, `aws`.
- Outbound internet from where you run Terraform: stage 40 pulls the chart from
  `https://portkey-ai.github.io/airs-gw-helm`, and stage 50 pulls the AWS Load
  Balancer Controller from `https://aws.github.io/eks-charts`.
- **A values.yaml downloaded from the AI Gateway (Portkey) console** — see the
  "Provide the console values.yaml" step below.
- **Bedrock model access enabled** in the target region (Bedrock console →
  *Model access*). This is the analog of GKE's `aiplatform.googleapis.com`
  enablement and cannot be done in this Terraform.

### Local apply with aws (authenticate first)

This project is applied **locally** — Terraform runs on your machine and talks to
AWS through the AWS CLI credential chain (the `aws` provider and the
kubernetes/helm providers, which mint a cluster token via `aws_eks_cluster_auth`):

```sh
aws configure            # or aws sso login / export AWS_PROFILE=...
aws sts get-caller-identity
```

Set `region` in your tfvars to the target region.

> **Egress IP matters.** Stages 40/50 apply through the cluster's *public* API
> endpoint, locked to `authorized_networks`. Add this machine's public IP as a
> `/32` (find it with `curl -s ifconfig.me`), or those stages can't connect. The
> same IP (or its `/24`) must also be in `allowed_source_ranges` to call the gateway
> through the WAF.

### Behind a TLS-inspecting proxy (corporate MITM)

Some corporate networks run a TLS-inspecting proxy that terminates and re-signs
HTTPS with an internal root CA. On such a network the tools here validate against a
CA that doesn't match the proxy's cert and fail. **Environment-specific** — on a
direct network, skip this section.

#### Fixes (per tool)

1. **Terraform (stages 40 & 50).** Set `cluster_insecure_tls = true` in
   `terraform.tfvars`. The kubernetes/helm providers then skip cert verification of
   the cluster endpoint and drop the cluster CA; the bearer token still
   authenticates. Leave `false` on a direct network.
2. **aws / kubectl / curl** — point them at the corporate root CA. Export the macOS
   keychain roots to a PEM bundle and register it:

   ```sh
   security find-certificate -a -p \
     /System/Library/Keychains/SystemRootCertificates.keychain > ~/corp-ca.pem
   security find-certificate -a -p \
     /Library/Keychains/System.keychain >> ~/corp-ca.pem
   export AWS_CA_BUNDLE=~/corp-ca.pem
   export CURL_CA_BUNDLE=~/corp-ca.pem
   ```
   For `kubectl`, either use that CA bundle or `--insecure-skip-tls-verify`.

### Provide the console values.yaml (before stage 40)

Save the `values.yaml` downloaded from the AI Gateway (Portkey) console as:

```text
EKS/terraform/40-aigateway/values.yaml
```

The `values_file` variable defaults to that path. It carries secrets and is
**gitignored**; never commit it. Verify:

```sh
git check-ignore 40-aigateway/values.yaml
```

Terraform overlays the AWS-specific settings on top (IRSA SA annotation,
`AWS_REGION`, `service.type=ClusterIP`, `ingress.enabled=false`).

## Apply

1. Copy and edit inputs:

   ```sh
   cp terraform.tfvars.example terraform.tfvars
   # edit region, state_bucket, authorized_networks, allowed_source_ranges, ...
   ```

2. **Stage 00** (local state) — creates the state bucket + lock table:

   ```sh
   cd 00-bootstrap
   terraform init
   terraform apply -var-file=../terraform.tfvars
   cd ..
   ```

3. Download the console `values.yaml` to `40-aigateway/values.yaml` (see above).

4. **Stages 10 → 50** — each uses the `s3` backend, so pass the bucket/table/region
   at init:

   ```sh
   for stage in 10-network 20-eks 30-iam 40-aigateway 50-ingress; do
     cd "$stage"
     terraform init \
       -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)" \
       -backend-config="dynamodb_table=$(terraform -chdir=../00-bootstrap output -raw state_lock_table)" \
       -backend-config="region=$(terraform -chdir=../00-bootstrap output -raw region)"
     terraform apply -var-file=../terraform.tfvars
     cd ..
   done
   ```

   (Cluster creation in stage 20 takes ~10–15 min.)

## Verify

1. `aws eks update-kubeconfig --name <cluster_name> --region <region>`;
   `kubectl get nodes`; `kubectl get pods -n airs-gw` (gateway + redis Running).
2. **IRSA** — `kubectl describe sa gateway-sa -n airs-gw` shows the
   `eks.amazonaws.com/role-arn` annotation; the pod has `AWS_ROLE_ARN` +
   `AWS_WEB_IDENTITY_TOKEN_FILE` injected.
3. Local smoke: `kubectl port-forward -n airs-gw svc/airs-gw 9000:8787` →
   `curl -s localhost:9000/v1/health`.
4. In the Portkey console add a Bedrock provider (assumed-role / default creds).
   From an **allowlisted** source, against the ALB (see 50-ingress README for the
   `--resolve` form), `curl -k https://<domain>/v1/chat/completions ...` → 200 and
   the request in Portkey Logs; a non-allowlisted IP → **403** (WAF). MCP reachable
   at `https://mcp.<domain>`.

## Notes & caveats

- **No static IP / nip.io.** The ALB exposes a DNS name — CNAME a real `domain` to
  the `alb_hostname` output, or use the placeholder `default_domain` with a Host
  header. See [50-ingress/README.md](50-ingress/README.md).
- **Bedrock has no account to create** — only model access enablement (console) +
  the IAM policy in stage 30. Unlike AKS's Azure OpenAI account.
- **Self-signed TLS** by default (browser/client warning; `curl -k`). Set
  `tls_cert_arn` to a real ACM cert to remove warnings.
- **Values precedence / secrets** — stage 40 passes the console `values.yaml` then
  the AWS overlay (overlay wins); the combined values are `sensitive()`-wrapped.
- **Chart pinned** to `1.2.0`; use `image_overrides` to run newer images on top.

## Teardown

Destroy in reverse order (50 → 00):

```sh
for stage in 50-ingress 40-aigateway 30-iam 20-eks 10-network; do
  terraform -chdir="$stage" destroy -var-file=../terraform.tfvars
done
# 00-bootstrap last; the state bucket has prevent_destroy — empty and remove it
# manually if desired (aws s3 rb s3://<bucket> --force).
terraform -chdir=00-bootstrap destroy -var-file=../terraform.tfvars
```
