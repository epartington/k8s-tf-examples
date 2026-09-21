# 50-ingress — Cloud Armor, managed cert, HTTPS Ingress

Puts the WAF-protected HTTPS load balancer in front of the gateway (and MCP). State
prefix `50-ingress`. Also talks to the cluster API, so the same egress-IP allowlist
and `cluster_insecure_tls` note as stage 40 apply.

## Creates

- `google_compute_security_policy.armor` — Cloud Armor policy: default-deny, allow
  `allowed_source_ranges`.
- `google_compute_managed_ssl_certificate.cert` — Google-managed cert. Domains:
  `<domain>` (or `<static-ip>.nip.io`) plus `mcp.<domain>` when MCP is enabled.
- `kubernetes_manifest.backend_config` — `BackendConfig` attaching the Cloud Armor
  policy and health check (`/v1/health` on the gateway port).
- `kubernetes_ingress_v1.gateway` — `gce` Ingress bound to the stage-10 static IP,
  HTTPS-only; gateway on the base host, MCP host-routed (`mcp.<domain>` → port 8788).
- **IAP scaffold (only when `iap_enabled=true`)** — `google_iap_brand.brand`,
  `google_iap_client.client`, `kubernetes_secret.iap_oauth`. Off by default.

## Reads

- `20-gke` — `endpoint` + `ca_certificate` for the provider.
- `10-network` — `static_ip_name` + `static_ip_address` for the Ingress / domains.
- `40-portkey` — `service_name`, ports, `mcp_enabled`, `backend_config_name`.

## Inputs used (from `../terraform.tfvars`)

`project_id`, `region`, `allowed_source_ranges`, `domain`, `mcp_domain`,
`iap_enabled` (+ `iap_support_email`, `iap_oauth_secret_name`), `cluster_insecure_tls`.

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

## Notes

- **`apply` returns fast, but the endpoint isn't live immediately.** The managed
  cert only goes `ACTIVE` once every SAN domain resolves to `ingress_ip` and the LB
  is serving — typically **15–60 min** with the nip.io fallback. Check with
  `gcloud compute ssl-certificates describe airs-gw-cert --global --format='value(managed.status)'`.
- With a real domain, point A records for both `<domain>` and `mcp.<domain>` at
  `ingress_ip`. The nip.io fallback resolves both automatically.
- **IAP** is a scaffold and depends on the deprecated IAP OAuth Admin API; Cloud
  Armor is the primary POV control. See the top-level [README](../README.md#notes--caveats).
- **Behind a TLS-inspecting proxy?** If `gcloud`/`kubectl`/`curl` (or the
  `cert-status` command above) fail with a cert-verification error, see
  [Behind a TLS-inspecting proxy (corporate MITM)](../README.md#behind-a-tls-inspecting-proxy-corporate-mitm)
  in the top-level README — the same proxy that requires `cluster_insecure_tls` here
  also affects the verify commands.
