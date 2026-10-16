# 50-ingress — WAF policy, TLS cert, App Gateway, AGIC, Ingress

Puts the WAF-protected HTTPS Application Gateway in front of the gateway (and MCP).
State key `50-ingress.tfstate`. Also talks to the cluster API, so the same
egress-IP allowlist and `cluster_insecure_tls` note as stage 40 apply.

## Creates

- `azurerm_web_application_firewall_policy.waf` — OWASP managed rules + an
  allowlist Block rule (block everything not in `allowed_source_ranges`).
- `azurerm_key_vault.kv` + `azurerm_key_vault_certificate.self_signed` — a
  self-signed cert for `<domain>` (+ `mcp.<domain>` SAN when MCP is enabled). Swap
  in a real cert with `tls_cert_keyvault_secret_id`.
- `azurerm_user_assigned_identity.appgw` (+ KV access policy) — lets the App
  Gateway read the cert from Key Vault.
- `azurerm_application_gateway.appgw` — WAF_v2 SKU bound to the WAF policy, the
  10-network public IP, and the KV cert. Created with a placeholder config; AGIC
  manages the listeners/pools/rules (their drift is in `ignore_changes`).
- `helm_release.agic` — the AGIC controller, authenticated to ARM via the
  stage-30 AGIC managed identity (Workload Identity).
- `kubernetes_ingress_v1.gateway` — class `azure-application-gateway`, gateway on
  the base host, MCP host-routed (`mcp.<domain>` → port 8788) when enabled.

## Reads

- `10-network` — `resource_group_name`, `location`, `appgw_subnet_id`,
  `appgw_public_ip_id`, `appgw_public_ip_address`.
- `20-aks` — kube_config values for the providers.
- `30-iam` — `agic_identity_client_id`, `agic_namespace`.
- `40-aigateway` — `namespace`, `service_name`, `service_port`, `mcp_enabled`,
  `mcp_service_port`.

## Inputs used (from `../terraform.tfvars`)

`subscription_id`, `state_resource_group`, `storage_account`,
`allowed_source_ranges`, `domain`, `mcp_domain`, `key_vault_name`,
`agic_chart_version`, `tls_cert_keyvault_secret_id` (optional),
`cluster_insecure_tls`.

## Run

```sh
cd 50-ingress
terraform init \
  -backend-config="resource_group_name=$(terraform -chdir=../00-bootstrap output -raw resource_group_name)" \
  -backend-config="storage_account_name=$(terraform -chdir=../00-bootstrap output -raw storage_account_name)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`ingress_ip`, `gateway_domain`, `gateway_url`, `mcp_domain`, `mcp_url`,
`waf_policy_name`.

## Notes

- **This is the most Azure-divergent stage.** GKE's single `gce` Ingress +
  Cloud Armor becomes: a WAF policy, a Key Vault cert, an explicit App Gateway
  (WAF_v2), the AGIC controller, and the Ingress. AGIC is installed **via Helm**
  (BYO App Gateway) so stage 20 stays cluster-only, matching GKE.
- **Allowlist chunking (parity with GKE's Cloud Armor fix).** GKE chunks the
  allowlist into 10-CIDR rules because Cloud Armor caps `src_ip_ranges` at 10 per
  rule. Azure WAF custom rules accept far more IP match values per rule, so the
  single `custom_rules` block (match on `allowed_source_ranges` with
  `negation_condition = true`, i.e. block anything **not** in the list) is
  sufficient here — no chunking needed for POV-scale allowlists.
- **AGIC chart version.** The chart is pulled from the MCR OCI registry
  (`oci://mcr.microsoft.com/azure-application-gateway/charts`). OCI installs
  generally require an explicit version — set `agic_chart_version` to a published
  version if `apply` fails to resolve the chart.
- **AGIC Workload Identity.** The Helm values set `armAuth.type = workloadIdentity`
  with the stage-30 AGIC identity client ID. The federated credential subject
  (`agic_namespace`/`agic_ksa_name` in stage 30) must match the namespace and SA
  the chart uses (defaults `default` / `ingress-azure`). Verify AGIC authenticates
  to ARM after install; if the chart version doesn't wire the WI pod label/SA
  annotation, add them.
- **Alternative: the AKS AGIC add-on.** Instead of Helm AGIC you can enable the
  `ingress_application_gateway` add-on on the cluster (stage 20) pointing at a
  pre-created App Gateway. That requires the App Gateway to exist *before* the
  cluster (move it into 10-network) and drops the AGIC identity — simpler to
  operate, but breaks the "stage 20 = cluster only" parity with GKE.
- **Self-signed TLS.** Browsers/clients warn on the self-signed cert; fine for a
  POV. Use `curl -k`, or set `tls_cert_keyvault_secret_id` to a real cert.

### Gateway TLS mode — `keyvault` (default) vs `cert-manager`

`gateway_tls_mode` selects how the gateway/MCP hosts get their TLS cert. The default is **unchanged
standalone behavior**; the second mode exists for running under a downstream apps layer.

| | `keyvault` (default) | `cert-manager` |
|---|---|---|
| Cert source | Key Vault cert (self-signed, or `tls_cert_keyvault_secret_id`) | Let's Encrypt via **in-cluster cert-manager** |
| Ingress wiring | `appgw-ssl-certificate` annotation | `cert-manager.io/cluster-issuer` annotation + `tls` block |
| Trusted in browsers | No (self-signed) unless you supply a real KV cert | Yes |
| **Cluster prerequisites** | **None** (self-contained) | **cert-manager + the named `ClusterIssuer` must already exist** |

- **Standalone / self-contained deploys: keep `keyvault`** (the default). Nothing else is required and
  this stage behaves exactly as before — the `cert-manager` code paths are inert.
- **`cert-manager` mode** only works when something has already installed cert-manager and a
  `ClusterIssuer` (name via `cert_manager_cluster_issuer`, default `letsencrypt-prod`) **in this
  cluster** — e.g. the companion apps project **`k8s-tf-examples-apps`** (`AKS/dns-tls/`), which also
  manages the public DNS zone + A records the ACME DNS-01 challenge and the hostnames need. Enabling it
  without that in place will leave the gateway Ingress with no usable cert. Set it in `terraform.tfvars`:
  ```hcl
  gateway_tls_mode = "cert-manager"
  domain           = "aigw.example.com"   # real FQDN with an A record -> ingress_ip
  mcp_domain       = "mcp.example.com"
  ```
- Switching modes is reversible: set it back to `keyvault` and re-apply to return to the self-signed
  Key Vault cert. (`ssl_certificate` is in the App Gateway's `ignore_changes`, so AGIC-uploaded certs —
  from this mode or from downstream apps Ingresses — are not reverted by a Terraform apply.)

### Who owns the gateway Ingress — `create_gateway_ingress` (default true)

`create_gateway_ingress` (default **true**) makes this stage create the gateway/MCP Ingress — the
normal self-contained behavior. Set it **false** only when a downstream apps project routes the gateway
through its **own** in-cluster controller instead of straight to the gateway Service — e.g.
`k8s-tf-examples-apps` sends the gateway host through **Traefik** so it can add an Okta-gated `/metrics`
route (AGIC cannot own the same host from two namespaces, so this stage must yield the Ingress).

- **Standalone: keep `true`.** This stage owns the gateway Ingress and TLS as usual.
- **`false`:** this stage creates no gateway Ingress; the apps project provides it (and owns the gateway
  host's TLS, so `gateway_tls_mode` is irrelevant). The App Gateway, WAF, cert machinery, and all other
  stages are unchanged. **Flipping this on an existing deploy briefly drops the gateway's external
  routing** until the apps-side Ingress is applied — do the two in quick succession.
- **Domains.** With a real domain, point A records for `<domain>` and
  `mcp.<domain>` at `ingress_ip`. The nip.io fallback resolves both automatically.
- **Behind a TLS-inspecting proxy?** If `az`/`kubectl`/`curl` fail with a
  cert-verification error, see
  [Behind a TLS-inspecting proxy (corporate MITM)](../README.md#behind-a-tls-inspecting-proxy-corporate-mitm)
  in the top-level README — the same proxy that requires `cluster_insecure_tls`
  here also affects the verify commands.
