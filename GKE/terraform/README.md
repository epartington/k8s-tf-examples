# POV: GKE + PRISMA AIRS / Portkey AI Gateway (Terraform)

A repeatable, POV-scale Terraform project that stands up an **isolated VPC** in an
**existing** GCP project and deploys the **PRISMA AIRS AI Gateway** (Portkey hybrid
data-plane) on a small **2-node private GKE cluster**, so the gateway can proxy
requests to **Google Vertex AI** models via Workload Identity.

Inbound traffic reaches the gateway through a **global external HTTPS load balancer**
locked down by **Cloud Armor** (IP allowlist). IAP is scaffolded but off by default.

Both the **gateway API** (port 8787) and the **MCP server** (port 8788) run in the same
pod and are fronted by that **same** load balancer, cert, and Cloud Armor policy — the
gateway on the primary domain and MCP on an `mcp.<domain>` host.

## Architecture

- **Isolated VPC** with a private, VPC-native GKE cluster (private nodes, public
  control-plane endpoint restricted to `authorized_networks`).
- **Cloud NAT** for egress (image pulls + reaching `api.portkey.ai` / `albus.portkey.ai`).
- **Workload Identity**: a GSA with `roles/aiplatform.user` bound to the gateway KSA;
  the gateway runs with `GCP_AUTH_MODE=workload`.
- **Hybrid deployment**: the data-plane runs in-cluster and syncs to the Portkey SaaS
  control plane, so it needs a Portkey license (`PORTKEY_CLIENT_AUTH`), an org ID
  (`ORGANISATIONS_TO_SYNC`), and registry credentials — all supplied via the
  `values.yaml` downloaded from the AI Gateway console.
- **Bundled Redis** (cache); log/analytics stores set to `control_plane`.
- **MCP**: `server_mode = "all"` (default) runs the MCP server alongside the gateway on
  port 8788. Stage 50 routes an `mcp.<domain>` host to that port through the same ALB, so
  MCP inherits the same TLS cert and Cloud Armor allowlist as the gateway.

## Layout — apply in numeric order

```text
GKE/terraform/
  terraform.tfvars.example   # copy to terraform.tfvars and edit
  00-bootstrap/   # GCS state bucket (LOCAL state) + enable project APIs
  10-network/     # VPC, subnet, Cloud Router + NAT, firewall, global static IP
  20-gke/         # private VPC-native GKE cluster + node pool, Workload Identity
  30-iam/         # gateway GSA (Vertex) + Workload Identity binding
  40-portkey/     # namespace + helm_release of airs-gw (console values.yaml + GCP overlay)
  50-ingress/     # Cloud Armor policy, managed cert, BackendConfig, Ingress
```

Each stage is an independent root module with its own GCS backend state (except
`00-bootstrap`, which uses local state to create the bucket). Later stages read
earlier outputs via `terraform_remote_state`.

## Prerequisites

- An existing GCP project and `gcloud` authenticated with sufficient IAM
  (project owner/editor for the POV, plus permission to create service accounts,
  security policies, and IAP resources).
- `terraform >= 1.5`, `kubectl`, `helm`, `gcloud`.
- The GKE auth plugin for `kubectl`: `gcloud components install gke-gcloud-auth-plugin`.
- Outbound internet from where you run Terraform: stage 40 pulls the chart from the
  official Helm repo `https://portkey-ai.github.io/airs-gw-helm`. (A copy of the chart
  is vendored under `../docs/airs-gw-helm-main/` for reference only.)
- **A values.yaml downloaded from the AI Gateway (Portkey) console** — it carries
  the hybrid credentials (license key, org ID, registry pull creds). See the
  "Provide the console values.yaml" step below.

### Local apply with gcloud (authenticate first)

This project is applied **locally** — Terraform runs on your machine and talks to
GCP through the Google Cloud CLI. Terraform's `google` provider (and the
`kubernetes`/`helm` providers in stages 40/50, which mint a token via
`google_client_config`) authenticate with **Application Default Credentials (ADC)**,
which are separate from your `gcloud` login. You must set up both:

```sh
gcloud auth login                        # authenticates the gcloud CLI itself
gcloud auth application-default login    # ADC — this is what Terraform uses
gcloud config set project <your-project>
```

Without the ADC step, `terraform plan` fails with a "could not find default
credentials" error even though `gcloud` commands work.

The account behind your ADC needs enough IAM to create the resources (project
owner/editor for a POV, or at minimum: create service accounts, GKE clusters,
and security policies).

> **Egress IP matters.** Stages 40/50 apply through the cluster's *public*
> control-plane endpoint, which is locked to `authorized_networks`. Add this
> machine's public IP as a `/32` to `authorized_networks` in your tfvars, or those
> stages can't connect. Find it with `curl -s ifconfig.me`. If your IP changes
> (dynamic/VPN), update the value and re-apply stage 20 before 40/50.

### Provide the console values.yaml (before stage 40)

Credentials are supplied via a `values.yaml` you download from the AI Gateway
(Portkey) console for this hybrid data plane. Save it as:

```text
GKE/terraform/40-portkey/values.yaml
```

The `values_file` variable defaults to that path, so stage 40 picks it up
automatically — see [40-portkey/values.yaml.example](40-portkey/values.yaml.example)
for the expected shape. This file carries secrets and is **gitignored**; never
commit it.

Terraform overlays the GCP-specific settings on top of your download (Workload
Identity SA annotation, container-native LB annotations, `GCP_AUTH_MODE=workload`,
and `ingress.enabled=false`), so you do **not** hand-set those in the file.

## Apply

1. Copy and edit inputs:

   ```sh
   cp terraform.tfvars.example terraform.tfvars
   # edit project_id, region, state_bucket, authorized_networks, allowed_source_ranges, ...
   ```

2. **Stage 00** (local state) — creates the state bucket and enables APIs:

   ```sh
   cd 00-bootstrap
   terraform init
   terraform apply -var-file=../terraform.tfvars
   cd ..
   ```

   Note the `state_bucket` output — it must equal the `state_bucket` in your tfvars.

3. Download the console `values.yaml` and save it to `40-portkey/values.yaml`
   (see above). Required before stage 40.

4. **Stages 10 → 50** — each uses the GCS backend, so pass the bucket at init:

   ```sh
   for stage in 10-network 20-gke 30-iam 40-portkey 50-ingress; do
     cd "$stage"
     terraform init -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)"
     terraform apply -var-file=../terraform.tfvars
     cd ..
   done
   ```

   (Or run each stage manually in order if you prefer to review plans individually.)

## Verify

1. Get credentials and check pods:

   ```sh
   gcloud container clusters get-credentials airs-gw-gke --zone <region>-a --project <project>
   kubectl get nodes
   kubectl get pods -n airs-gw          # gateway + redis Running
   ```

2. **Workload Identity** resolves to the GSA (not the node SA):

   ```sh
   kubectl exec -n airs-gw deploy/airs-gw -- \
     wget -qO- --header "Metadata-Flavor: Google" \
     http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
   # -> airs-gw-gateway@<project>.iam.gserviceaccount.com
   ```

3. Local smoke test:

   ```sh
   kubectl port-forward -n airs-gw svc/airs-gw 9000:8787
   curl -s localhost:9000/v1/health
   ```

4. In the Portkey control plane, add a `@vertex-ai` provider (auth type `workload`,
   your project + region). Then from an **allowlisted** source:

   ```sh
   curl https://<domain>/v1/chat/completions \
     -H "x-portkey-api-key: <key>" \
     -H "x-portkey-provider: @vertex-ai" \
     -H "content-type: application/json" \
     -d '{"model":"@vertex-ai/gemini-2.5-flash","messages":[{"role":"user","content":"hi"}]}'
   ```

   Confirm a 200 and that the request appears in Portkey Logs. A request from a
   non-allowlisted IP should return **403** (Cloud Armor).

5. **MCP endpoint** — reachable on the `mcp_url` output (`https://mcp.<domain>`), through
   the same cert and Cloud Armor policy. Point your MCP client at that URL, or smoke-test
   the port directly:

   ```sh
   kubectl port-forward -n airs-gw svc/airs-gw 9788:8788
   # then connect your MCP client to http://localhost:9788
   ```

   From a non-allowlisted IP, `https://mcp.<domain>` returns **403** just like the gateway.

## Notes & caveats

- **TLS provisioning**: the Google-managed cert only goes `ACTIVE` once the domain
  resolves to the load balancer IP and the LB is serving. With a real domain, point
  an A record at the `ingress_ip` output. With the **nip.io fallback** (empty
  `domain`), the cert domain is `<ip>.nip.io`; provisioning can take 15–60 min.
- **IAP vs API traffic**: IAP authenticates browser/user identities and would block
  plain API calls, so it is **off by default**. Cloud Armor is the primary POV
  control. The `iap_enabled=true` path is only a scaffold: it uses
  `google_iap_brand` / `google_iap_client`, which depend on the IAP OAuth Admin API
  that Google deprecated after July 2025. To actually enable IAP today, create the
  OAuth client manually and reference its credentials secret instead of relying on
  those resources.
- **Values precedence**: stage 40 passes two value sources to Helm — your console
  `values.yaml` first, then a Terraform-generated GCP overlay. The overlay wins where
  they intersect, so it always sets the Workload Identity SA annotation, the
  container-native LB annotations, `GCP_AUTH_MODE=workload`, and `ingress.enabled=false`
  regardless of the download.
- **Redis / stores**: Redis, log store, and analytics store come from your console
  `values.yaml` (the overlay does not touch them), so they reflect how you configured
  the data plane in the console.
- **Image version**: repo/tag come from the console `values.yaml` (or the chart's
  `appVersion` if unset there). Leave `image_repository`/`image_tag` empty to use them;
  set them only to swap registries or hotfix a specific tag.
- **MCP routing**: MCP is exposed **host-based** (`mcp.<domain>`) rather than on a
  `/mcp` path, because the GCE Ingress does not strip path prefixes — a dedicated host with
  a `/*` rule forwards every path to port 8788 regardless of the MCP server's internal
  layout. The MCP host is added as a SAN on the same managed cert, so the cert only goes
  `ACTIVE` once **both** `<domain>` and `mcp.<domain>` resolve to the LB IP (automatic with
  the nip.io fallback). The single BackendConfig's health check probes `/v1/health` on the
  gateway port; since MCP shares the pod, its backend is health-checked there too. Set
  `server_mode = ""` to run gateway-only and skip MCP exposure entirely.
- **Global vs regional LB**: this uses a **global** external ALB (`gce` ingress class),
  which needs the global static IP but **not** a `REGIONAL_MANAGED_PROXY` subnet. Add
  one in `10-network` only if you switch to a regional/internal LB.

## Teardown

Destroy in reverse order (50 → 00):

```sh
for stage in 50-ingress 40-portkey 30-iam 20-gke 10-network; do
  terraform -chdir="$stage" destroy -var-file=../terraform.tfvars
done
# 00-bootstrap last; the state bucket has prevent_destroy — empty and remove it manually if desired.
terraform -chdir=00-bootstrap destroy -var-file=../terraform.tfvars
```
