# 50-ingress — Cloud Armor, managed cert, HTTPS Ingress

Puts the WAF-protected HTTPS load balancer in front of the gateway (and MCP). State
prefix `50-ingress`. Also talks to the cluster API, so the same egress-IP allowlist
and `cluster_insecure_tls` note as stage 40 apply.

## Creates

- `google_compute_security_policy.armor` — Cloud Armor policy: default-deny, allow
  `allowed_source_ranges`.
- `google_compute_managed_ssl_certificate.cert` — Google-managed cert. Domains:
  `<domain>` (or `<static-ip>.nip.io`) plus `mcp.<domain>` when MCP is enabled.
  **Skipped when `tls_cert_name` is set** (bring-your-own pre-shared cert).
- `kubernetes_manifest.backend_config` — `BackendConfig` attaching the Cloud Armor
  policy and health check (`/v1/health` on the gateway port).
- `kubernetes_ingress_v1.gateway` — `gce` Ingress bound to the stage-10 static IP,
  HTTPS-only; gateway on the base host, MCP host-routed (`mcp.<domain>` → port 8788).
- **IAP scaffold (only when `iap_enabled=true`)** — `google_iap_brand.brand`,
  `google_iap_client.client`, `kubernetes_secret.iap_oauth`. Off by default.

## Reads

- `20-gke` — `endpoint` + `ca_certificate` for the provider.
- `10-network` — `static_ip_name` + `static_ip_address` for the Ingress / domains.
- `40-aigateway` — `service_name`, ports, `mcp_enabled`, `backend_config_name`.

## Inputs used (from `../terraform.tfvars`)

`project_id`, `region`, `allowed_source_ranges`, `domain`, `mcp_domain`,
`tls_cert_name` (optional, BYO cert), `iap_enabled` (+ `iap_support_email`,
`iap_oauth_secret_name`), `cluster_insecure_tls`.

## Run

```sh
cd 50-ingress
terraform init -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`ingress_ip`, `gateway_domain`, `gateway_url`, `mcp_domain`, `mcp_url`,
`security_policy_name`.

## Validate end-to-end

Once the cert is `ACTIVE` (see Notes), test from a host **inside
`allowed_source_ranges`** (a non-allowlisted source gets a `403` from Cloud Armor).
The call targets the exposed frontend domain — pull it from the outputs so you don't
hand-copy the IP:

Set these four variables, then run the command block unchanged:

```sh
# --- fill in ---
PORTKEY_API_KEY="..."       # Portkey API/virtual/workspace key from the control plane
PROVIDER_SLUG="vertex-ai"   # Vertex provider slug you configured (auth type: workload)
MODEL="gemini-2.5-flash"    # a Vertex model available in your vertex_region
# --- derived ---
DOMAIN=$(terraform -chdir=50-ingress output -raw gateway_domain)   # e.g. 34.x.x.x.nip.io

curl -s "https://${DOMAIN}/v1/chat/completions" \
  -H "content-type: application/json" \
  -H "x-portkey-api-key: ${PORTKEY_API_KEY}" \
  -H "x-portkey-provider: @${PROVIDER_SLUG}" \
  -d "{
        \"model\": \"@${PROVIDER_SLUG}/${MODEL}\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Reply with the single word: pong\"}]
      }"
```

`PROVIDER_SLUG` is used in both the `x-portkey-provider` header and the `model`
prefix, so setting it once covers both.

Expect a `200` with a completion, and the request visible in **Portkey → Logs**.
Then confirm the WAF from a **non-allowlisted** IP:

```sh
curl -s -o /dev/null -w '%{http_code}\n' "https://${DOMAIN}/v1/health"   # -> 403
```

MCP validates the same way against `mcp_url` (`https://mcp.<domain>`), through the
same cert and Cloud Armor policy.

> The nip.io domain is real DNS, so this works from any allowlisted machine without
> editing `/etc/hosts`. With a self-managed domain instead, ensure its A record
> points at `ingress_ip` first.

## Notes

- **`apply` returns fast, but the endpoint isn't live immediately.** The managed
  cert only goes `ACTIVE` once every SAN domain resolves to `ingress_ip` and the LB
  is serving — typically **15–60 min** with the nip.io fallback. Check with
  `gcloud compute ssl-certificates describe airs-gw-cert --global --format='value(managed.status)'`.
- With a real domain, point A records for both `<domain>` and `mcp.<domain>` at
  `ingress_ip`. The nip.io fallback resolves both automatically.
- **Bring your own cert** (parallel to AKS `tls_cert_keyvault_secret_id` / EKS
  `tls_cert_arn`): create a global pre-shared SSL cert first
  (`gcloud compute ssl-certificates create airs-gw-byo --certificate=cert.pem
  --private-key=key.pem --global`), then set `tls_cert_name = "airs-gw-byo"`. The
  Ingress references it and the managed cert is skipped (no `ACTIVE`-wait, no
  domain-resolves-to-IP dependency). The Google-managed cert remains the default
  (free, auto-renewed) when `tls_cert_name` is empty.
- **IAP** is a scaffold and depends on the deprecated IAP OAuth Admin API; Cloud
  Armor is the primary POV control. See the top-level [README](../README.md#notes--caveats).
- **Behind a TLS-inspecting proxy?** If `gcloud`/`kubectl`/`curl` (or the
  `cert-status` command above) fail with a cert-verification error, see
  [Behind a TLS-inspecting proxy (corporate MITM)](../README.md#behind-a-tls-inspecting-proxy-corporate-mitm)
  in the top-level README — the same proxy that requires `cluster_insecure_tls` here
  also affects the verify commands.
