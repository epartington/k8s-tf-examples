# 50-ingress — WAF web ACL, ACM cert, ALB controller, Ingress

Puts the WAF-protected HTTPS ALB in front of the gateway (and MCP). State key
`50-ingress.tfstate`. Also talks to the cluster API, so the same egress-IP
allowlist and `cluster_insecure_tls` note as stage 40 apply.

## Creates

- `aws_wafv2_web_acl.this` (+ `aws_wafv2_ip_set` when an allowlist is set) —
  default-block + allow-listed-IPs, associated with the ALB via the Ingress
  annotation. Open (default allow) when `allowed_source_ranges` is empty.
- ACM cert — self-signed by default (`tls_private_key` + `tls_self_signed_cert` +
  `aws_acm_certificate` import) for `<domain>` (+ `mcp.<domain>` SAN). Supply a real
  cert with `tls_cert_arn`.
- `helm_release.lb_controller` — the AWS Load Balancer Controller, authenticated via
  the stage-30 IRSA role; it provisions the ALB from the Ingress.
- `kubernetes_ingress_v1.gateway` — class `alb`, internet-facing, HTTPS (cert) +
  HTTP→HTTPS redirect, WAF ACL attached; gateway on the base host, MCP host-routed
  (`mcp.<domain>` → port 8788) when enabled.

## Reads

- `10-network` — `vpc_id`.
- `20-eks` — `cluster_name` + endpoint/CA for the providers.
- `30-iam` — `lb_controller_role_arn`, namespace, SA name.
- `40-aigateway` — `namespace`, `service_name`, `service_port`, `mcp_enabled`,
  `mcp_service_port`.

## Inputs used (from `../terraform.tfvars`)

`region`, `state_bucket`, `allowed_source_ranges`, `domain`, `default_domain`,
`mcp_domain`, `tls_cert_arn` (optional), `lb_controller_chart_version`,
`cluster_insecure_tls`.

## Run

```sh
cd 50-ingress
terraform init \
  -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)" \
  -backend-config="dynamodb_table=$(terraform -chdir=../00-bootstrap output -raw state_lock_table)" \
  -backend-config="region=$(terraform -chdir=../00-bootstrap output -raw region)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

`apply` waits for the ALB to be provisioned (`wait_for_load_balancer`), so the
`alb_hostname` output is populated.

## Outputs

`alb_hostname` (the ALB DNS name), `gateway_domain`, `gateway_url`, `mcp_domain`,
`mcp_url`, `waf_web_acl_arn`.

## Notes

- **No static IP / nip.io.** Unlike GKE/AKS, an ALB has a **DNS name**, not an IP,
  so there's no nip.io fallback. Reach the gateway by either: setting a real
  `domain` and CNAME-ing it to `alb_hostname`, or hitting the ALB with a Host header
  for the placeholder `default_domain` (`airs-gw.local`):
  `curl -k --resolve airs-gw.local:443:$(dig +short <alb_hostname> | head -1) https://airs-gw.local/v1/health`.
- **Allowlist chunking not needed.** AWS WAF accepts far more IP match values per
  rule than Cloud Armor's 10-CIDR cap, so a single IP-set rule suffices (parity note
  with GKE's chunking).
- **Self-signed TLS.** Browsers/clients warn; use `curl -k`, or set `tls_cert_arn`
  to a real ACM cert (DNS-validated on a domain you control).
- **LB controller chart version.** Leave `lb_controller_chart_version` empty for
  latest, or pin for reproducibility.
- **Behind a TLS-inspecting proxy?** See
  [Behind a TLS-inspecting proxy (corporate MITM)](../README.md#behind-a-tls-inspecting-proxy-corporate-mitm)
  in the top-level README.
