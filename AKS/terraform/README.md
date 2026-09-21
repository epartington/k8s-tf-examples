# POV: AKS + PRISMA AIRS / Portkey AI Gateway (Terraform)

A repeatable, POV-scale Terraform project that stands up an **isolated VNet** in an
**existing** Azure subscription and deploys the **PRISMA AIRS AI Gateway** (Portkey hybrid
data-plane) on a small **2-node private AKS cluster**, so the gateway can proxy requests to
**Azure OpenAI** models via **Entra Workload Identity** (federated identity, no static keys).

Inbound traffic reaches the gateway through a **public HTTPS Application Gateway** (WAF_v2)
locked down by a **WAF policy** (IP allowlist, default-deny).

Both the **gateway API** (port 8787) and the **MCP server** (port 8788) run in the same pod
and are fronted by that **same** Application Gateway, cert, and WAF policy — the gateway on
the primary domain and MCP on an `mcp.<domain>` host.

This is the Azure port of the [GKE reference](../../GKE/terraform/README.md); it preserves
the same six numbered stages and the same console-`values.yaml` + Terraform-overlay Helm
pattern. See [../README.md](../README.md) for the GKE→Azure mapping table.

## Architecture

- **Isolated VNet** with a VNet-integrated AKS cluster (Azure CNI overlay, public API
  server endpoint restricted to `authorized_networks`).
- **NAT Gateway** for egress (image pulls + reaching `api.portkey.ai` / `albus.portkey.ai`).
- **Entra Workload Identity**: a user-assigned managed identity with the
  `Cognitive Services OpenAI User` role, federated to the gateway KSA via the cluster OIDC
  issuer — no static keys in the pod.
- **Hybrid deployment**: the data-plane runs in-cluster and syncs to the Portkey SaaS
  control plane, so it needs a Portkey license (`PORTKEY_CLIENT_AUTH`), an org ID
  (`ORGANISATIONS_TO_SYNC`), and registry credentials — all supplied via the
  `values.yaml` downloaded from the AI Gateway console.
- **Bundled Redis** (cache); log/analytics stores set to `control_plane`.
- **MCP**: `server_mode = "all"` (default) runs the MCP server alongside the gateway on
  port 8788. Stage 50 routes an `mcp.<domain>` host to that port through the same App
  Gateway, so MCP inherits the same TLS cert and WAF policy as the gateway.

## Layout — apply in numeric order

```text
AKS/terraform/
  terraform.tfvars.example   # copy to terraform.tfvars and edit
  00-bootstrap/   # state RG + Storage Account/container (LOCAL state) + register providers
  10-network/     # VNet, subnets (aks + appgw), NAT Gateway + egress IP, NSG, App Gateway IP
  20-aks/         # private-node AKS + node pool, OIDC issuer + Workload Identity
  30-iam/         # gateway UAMI + AGIC UAMI (federated to KSAs) + Azure OpenAI + role
  40-portkey/     # namespace + helm_release of airs-gw (console values.yaml + Azure overlay)
  50-ingress/     # WAF policy, Key Vault self-signed cert, App Gateway (WAF_v2), AGIC, Ingress
```

Each stage is an independent root module with its own `azurerm` backend state (except
`00-bootstrap`, which uses local state to create the state Storage Account). Later stages
read earlier outputs via `terraform_remote_state`. Each stage folder has its own README
with the resources it creates, its inputs, and its run commands.

## Prerequisites

- An existing Azure subscription and the `az` CLI authenticated with sufficient RBAC
  (Owner/Contributor + User Access Administrator for the POV, since the stages create role
  assignments and federated credentials).
- `terraform >= 1.5`, `kubectl`, `helm`, `az`.
- Outbound internet from where you run Terraform: stage 40 pulls the chart from the
  official Helm repo `https://portkey-ai.github.io/airs-gw-helm`, and stage 50 pulls AGIC
  from `oci://mcr.microsoft.com/azure-application-gateway/charts`. (A copy of the airs-gw
  chart is vendored under `../../GKE/docs/airs-gw-helm-main/` for reference only.)
- **A values.yaml downloaded from the AI Gateway (Portkey) console** — it carries the
  hybrid credentials (license key, org ID, registry pull creds). See the "Provide the
  console values.yaml" step below.

### Local apply with az (authenticate first)

This project is applied **locally** — Terraform runs on your machine and talks to Azure
through the Azure CLI. Terraform's `azurerm` provider (and the `kubernetes`/`helm`
providers in stages 40/50, which read the cluster `kube_config`) authenticate through your
`az` login:

```sh
az login
az account set --subscription <subscription-id>
```

Set `subscription_id` in your tfvars to the same subscription. The signed-in account needs
enough RBAC to create the resources (Owner/Contributor + User Access Administrator for a
POV, or at minimum: create resource groups, storage, VNets, AKS clusters, managed
identities, role assignments, Key Vault, and Application Gateway).

> **Egress IP matters.** Stages 40/50 apply through the cluster's *public* API server
> endpoint, which is locked to `authorized_networks`. Add this machine's public IP as a
> `/32` to `authorized_networks` in your tfvars, or those stages can't connect. Find it
> with `curl -s ifconfig.me`. If your IP changes (dynamic/VPN), update the value and
> re-apply stage 20 before 40/50. The same IP (or its `/24`) must also be in
> `allowed_source_ranges` to call the gateway through the WAF.

### Behind a TLS-inspecting proxy (corporate MITM)

Some corporate networks run a TLS-inspecting proxy that terminates and re-signs HTTPS with
an internal root CA. On such a network the tools here validate against a CA that doesn't
match the proxy's cert and fail. This is **environment-specific** — on a direct network you
skip this whole section and leave every default as-is.

#### Symptoms

- `terraform apply` (stage 40/50): `Error: … tls: failed to verify certificate: x509:
  certificate signed by unknown authority` when the kubernetes/helm providers reach the
  cluster endpoint.
- `az` / `kubectl` / `curl`: `SSL certificate problem` / `certificate signed by unknown
  authority`.

Root cause: these tools validate against an **explicit** CA (Terraform's
`cluster_ca_certificate`, the kubeconfig CA) or their **own bundled** CA (az, curl, Go),
not the macOS system keychain — so the corporate root isn't trusted.

#### Fixes (per tool)

1. **Terraform (stages 40 & 50).** Set in `terraform.tfvars`:

   ```hcl
   cluster_insecure_tls = true
   ```

   This makes the kubernetes/helm providers skip cert verification of the cluster endpoint
   and drop `cluster_ca_certificate`; the client certificate from the kube_config still
   authenticates. Leave `false` (the default) on a direct network.

2. **az** — point it at the corporate root CA. Export the macOS keychain roots (which
   include the corporate CA) to a PEM bundle and register it:

   ```sh
   security find-certificate -a -p \
     /System/Library/Keychains/SystemRootCertificates.keychain > ~/corp-ca.pem
   security find-certificate -a -p \
     /Library/Keychains/System.keychain >> ~/corp-ca.pem
   export REQUESTS_CA_BUNDLE=~/corp-ca.pem     # az is Python-based
   export CURL_CA_BUNDLE=~/corp-ca.pem          # curl and other tools
   ```

   (`az config set core.ca_certs=~/corp-ca.pem` also works for persistent config.)

3. **kubectl** — either use the CA bundle above (set `certificate-authority` on the
   cluster) or skip verification per command / in kubeconfig:

   ```sh
   kubectl get pods -n airs-gw --insecure-skip-tls-verify
   # or make it stick (must drop the CA data, which conflicts with skip-verify):
   CTX=airs-gw-aks
   kubectl config unset "clusters.${CTX}.certificate-authority-data"
   kubectl config set-cluster "$CTX" --insecure-skip-tls-verify=true
   ```

4. **curl** — `curl -k https://…` for a one-off, or rely on `CURL_CA_BUNDLE` above. (Note
   the gateway's own self-signed TLS cert also warrants `curl -k` — see Notes.)

> Skipping verification is acceptable for a POV behind a **known, trusted** corporate
> proxy. Preferring the CA-bundle route (az/curl/requests) keeps verification on; only
> Terraform and kubectl fall back to skip-verify here.

### Provide the console values.yaml (before stage 40)

Credentials are supplied via a `values.yaml` you download from the AI Gateway (Portkey)
console for this hybrid data plane. Save it as:

```text
AKS/terraform/40-portkey/values.yaml
```

The `values_file` variable defaults to that path, so stage 40 picks it up automatically —
see [40-portkey/values.yaml.example](40-portkey/values.yaml.example) for the expected
shape. This file carries secrets and is **gitignored**; never commit it. Verify before
adding anything under `40-portkey/`:

```sh
git check-ignore 40-portkey/values.yaml
```

Terraform overlays the Azure-specific settings on top of your download (Workload Identity
SA annotation + pod label, `service.type=ClusterIP`, and `ingress.enabled=false`), so you
do **not** hand-set those in the file.

## Apply

1. Copy and edit inputs:

   ```sh
   cp terraform.tfvars.example terraform.tfvars
   # edit subscription_id, location, storage_account, authorized_networks,
   #      allowed_source_ranges, ...
   ```

2. **Stage 00** (local state) — creates the state Storage Account and registers providers:

   ```sh
   cd 00-bootstrap
   terraform init
   terraform apply -var-file=../terraform.tfvars
   cd ..
   ```

   Note the `resource_group_name` / `storage_account_name` outputs — they must equal the
   `state_resource_group` / `storage_account` in your tfvars.

3. Download the console `values.yaml` and save it to `40-portkey/values.yaml` (see above).
   Required before stage 40.

4. **Stages 10 → 50** — each uses the `azurerm` backend, so pass the state RG + account at
   init:

   ```sh
   for stage in 10-network 20-aks 30-iam 40-portkey 50-ingress; do
     cd "$stage"
     terraform init \
       -backend-config="resource_group_name=$(terraform -chdir=../00-bootstrap output -raw resource_group_name)" \
       -backend-config="storage_account_name=$(terraform -chdir=../00-bootstrap output -raw storage_account_name)"
     terraform apply -var-file=../terraform.tfvars
     cd ..
   done
   ```

   (Or run each stage manually in order if you prefer to review plans individually. Cluster
   creation in stage 20 takes ~5–10 min.)

## Verify

1. Get credentials and check pods:

   ```sh
   az aks get-credentials -g <resource_group> -n <cluster_name>
   kubectl get nodes
   kubectl get pods -n airs-gw          # gateway + redis Running
   ```

2. **Workload Identity** — the KSA carries the client-id annotation and the pod has the
   projected token:

   ```sh
   kubectl describe sa gateway-sa -n airs-gw     # shows azure.workload.identity/client-id
   kubectl describe pod -n airs-gw -l app.kubernetes.io/name=airs-gw | grep -i azure-identity-token
   ```

3. Local smoke test:

   ```sh
   kubectl port-forward -n airs-gw svc/airs-gw 9000:8787
   curl -s localhost:9000/v1/health
   ```

4. In the Portkey control plane, add an Azure OpenAI provider (Workload Identity if the
   gateway build supports it, else the API key — see Notes). Then from an **allowlisted**
   source:

   ```sh
   curl -k https://<domain>/v1/chat/completions \
     -H "x-portkey-api-key: <key>" \
     -H "x-portkey-provider: @azure-openai" \
     -H "content-type: application/json" \
     -d '{"model":"@azure-openai/gpt-4o-mini","messages":[{"role":"user","content":"hi"}]}'
   ```

   Confirm a 200 and that the request appears in Portkey Logs. A request from a
   non-allowlisted IP should return **403** (WAF policy). (`-k` because the POV cert is
   self-signed.)

5. **MCP endpoint** — reachable on the `mcp_url` output (`https://mcp.<domain>`), through
   the same cert and WAF policy. Point your MCP client at that URL, or smoke-test the port
   directly:

   ```sh
   kubectl port-forward -n airs-gw svc/airs-gw 9788:8788
   # then connect your MCP client to http://localhost:9788
   ```

   From a non-allowlisted IP, `https://mcp.<domain>` returns **403** just like the gateway.

## Notes & caveats

- **Azure OpenAI auth mode (open item).** The chart documents Vertex (`GCP_AUTH_MODE`) and
  Bedrock auth, not Azure OpenAI. The primary path here is Entra Workload Identity (the
  overlay sets the SA annotation + pod label). If the gateway build can't mint an Entra
  token for Azure OpenAI, fall back to providing the model **API key** via the console
  `values.yaml` and configuring the Azure OpenAI provider in the Portkey console with that
  key. Confirm the working path once the gateway is running.
- **Self-signed TLS.** The POV generates a self-signed cert into Key Vault, so browsers and
  clients warn — use `curl -k` and expect a browser warning. Set
  `tls_cert_keyvault_secret_id` to a real cert to remove the warnings; Azure App Gateway
  has no free auto-managed cert equivalent to GKE's Google-managed cert.
- **AGIC delivery.** AGIC is installed **via Helm** in stage 50 against a BYO App Gateway
  (WAF_v2), so stage 20 stays cluster-only and the layout matches GKE. The App Gateway is
  created with a placeholder config and `lifecycle { ignore_changes }` on the blocks AGIC
  manages. The AKS AGIC add-on is a documented alternative (see
  [50-ingress/README.md](50-ingress/README.md)) but requires the App Gateway before the
  cluster.
- **Values precedence.** Stage 40 passes two value sources to Helm — your console
  `values.yaml` first, then a Terraform-generated Azure overlay. The overlay wins where
  they intersect, so it always sets the Workload Identity SA annotation + pod label,
  `service.type=ClusterIP`, and `ingress.enabled=false` regardless of the download.
- **Redis / stores.** Redis, log store, and analytics store come from your console
  `values.yaml` (the overlay does not touch them), so they reflect how you configured the
  data plane in the console.
- **Image version.** Repo/tag come from the console `values.yaml` (or the chart's
  `appVersion` if unset there). Leave `image_repository`/`image_tag` empty to use them; set
  them only to swap registries or hotfix a specific tag.
- **MCP routing.** MCP is exposed **host-based** (`mcp.<domain>`) rather than on a `/mcp`
  path, matching GKE — a dedicated host with a `/*` rule forwards every path to port 8788.
  The MCP host is added as a SAN on the same cert. Set `server_mode = ""` to run
  gateway-only and skip MCP exposure entirely.
- **Region.** Pick a `location` where Azure OpenAI and your chosen model are available; the
  `create_openai` deployment's model/SKU must exist in that region (`openai_location`
  overrides the region for the OpenAI account only).

## Teardown

Destroy in reverse order (50 → 00):

```sh
for stage in 50-ingress 40-portkey 30-iam 20-aks 10-network; do
  terraform -chdir="$stage" destroy -var-file=../terraform.tfvars
done
# 00-bootstrap last; the state Storage Account has prevent_destroy — empty and remove it
# manually if desired.
terraform -chdir=00-bootstrap destroy -var-file=../terraform.tfvars
```
