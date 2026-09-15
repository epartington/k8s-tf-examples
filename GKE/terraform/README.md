# POV: GKE + PRISMA AIRS / Portkey AI Gateway (Terraform)

A repeatable, POV-scale Terraform project that stands up an **isolated VPC** in an
**existing** GCP project and deploys the **PRISMA AIRS AI Gateway** (Portkey hybrid
data-plane) on a small **2-node private GKE cluster**, so the gateway can proxy
requests to **Google Vertex AI** models via Workload Identity.

Inbound traffic reaches the gateway through a **global external HTTPS load balancer**
locked down by **Cloud Armor** (IP allowlist). IAP is scaffolded but off by default.

## Architecture

- **Isolated VPC** with a private, VPC-native GKE cluster (private nodes, public
  control-plane endpoint restricted to `authorized_networks`).
- **Cloud NAT** for egress (image pulls + reaching `api.portkey.ai` / `albus.portkey.ai`).
- **Workload Identity**: a GSA with `roles/aiplatform.user` bound to the gateway KSA;
  the gateway runs with `GCP_AUTH_MODE=workload`.
- **Hybrid deployment**: the data-plane runs in-cluster and syncs to the Portkey SaaS
  control plane, so it needs a Portkey license (`PORTKEY_CLIENT_AUTH`), an org ID
  (`ORGANISATIONS_TO_SYNC`), and registry credentials — all read from Secret Manager.
- **Bundled Redis** (cache); log/analytics stores set to `control_plane`.

## Layout — apply in numeric order

```text
GKE/terraform/
  terraform.tfvars.example   # copy to terraform.tfvars and edit
  00-bootstrap/   # GCS state bucket (LOCAL state) + enable project APIs
  10-network/     # VPC, subnet, Cloud Router + NAT, firewall, global static IP
  20-gke/         # private VPC-native GKE cluster + node pool, Workload Identity
  30-iam/         # gateway GSA (Vertex) + Workload Identity binding
  40-portkey/     # namespace, Secret Manager reads, helm_release of airs-gw
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
- The vendored chart at `../docs/airs-gw-helm-main/charts/airs-gw` (already in-repo).
- **Portkey enterprise credentials** (from your Portkey account): the hybrid
  license key, your org ID, and registry username/password.

### Create the Secret Manager secrets (before stage 40)

APIs are enabled by stage 00, so create these after applying `00-bootstrap`:

```sh
printf '%s' "<PORTKEY_CLIENT_AUTH>"    | gcloud secrets create aigw-client-auth  --data-file=- --project "$PROJECT"
printf '%s' "<ORGANISATIONS_TO_SYNC>"  | gcloud secrets create aigw-org-id       --data-file=- --project "$PROJECT"
printf '%s' "<REGISTRY_USERNAME>"      | gcloud secrets create aigw-docker-user  --data-file=- --project "$PROJECT"
printf '%s' "<REGISTRY_PASSWORD>"      | gcloud secrets create aigw-docker-pass  --data-file=- --project "$PROJECT"
```

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

3. Create the four Secret Manager secrets (see above).

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
- **Redis wiring**: the chart auto-wires the bundled Redis (`redis://airs-gw-redis:6379`)
  via its own secret. We deliberately do **not** set `REDIS_URL`/`CACHE_STORE` so the
  chart owns that, avoiding the `redis://redis:6379` value shown in some docs.
- **Image registry**: the vendored chart defaults to `registry.portkey.ai/...`;
  `docs/gcp.md` uses `docker.io/portkeyai/...`. `image_repository` and
  `registry_server` are variables — set them to match the creds you were issued.
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
