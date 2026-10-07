# 40-aigateway — namespace + Helm release of the gateway

Deploys the PRISMA AIRS / Portkey `airs-gw` chart into the cluster. State prefix
`40-aigateway`. This is the first stage that **talks to the cluster API** (the
kubernetes and helm providers), so this machine's egress IP must be in
`authorized_networks`.

## Prerequisite — the console `values.yaml`

Download the `values.yaml` from the AI Gateway (Portkey) console and save it here:

```text
40-aigateway/values.yaml
```

It carries the hybrid credentials (license `PORTKEY_CLIENT_AUTH`, `ORGANISATIONS_TO_SYNC`,
registry pull creds). It is **gitignored — never commit it.** The `values_file` var
defaults to this path. See [values.yaml.example](values.yaml.example) for the shape.
Stage 40 can't `plan`/`apply` (or `validate`) without it — the config uses `file()`.

## Creates

- `kubernetes_namespace.airs` — the `namespace`.
- `helm_release.airs_gw` — the `airs-gw` chart from `chart_repository`, with values
  layered as **[console `values.yaml`, Terraform GCP overlay]** (overlay wins). The
  overlay sets: KSA `serviceAccount.create` + `iam.gke.io/gcp-service-account`
  annotation (Workload Identity), `GCP_AUTH_MODE=workload`, `SERVER_MODE`/`MCP_PORT`,
  Service annotations (NEG + `backend-config`), and `ingress.enabled=false`.

## Reads

- `20-gke` — `endpoint` + `ca_certificate` to configure the providers.
- `30-iam` — `gsa_email` for the KSA annotation.

## Inputs used (from `../terraform.tfvars`)

`project_id`, `region`, `state_bucket`, `namespace`, `ksa_name`, `server_mode`,
`mcp_port`, `gateway_port`, optional `chart_version` / `image_repository` /
`image_tag`, and **`cluster_insecure_tls`** (see Notes).

## Run

```sh
cd 40-aigateway
# save values.yaml here first (see above)
terraform init -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

`helm_release` has `wait=true`, so `apply` blocks until the gateway + Redis pods are
Ready (pulls the enterprise image via the console pull secret). Bad image creds
surface here as a pod-start failure.

## Outputs

`namespace`, `release_name`, `service_name`, `service_port`, `mcp_enabled`,
`mcp_service_port`, `backend_config_name`. Stage 50 consumes these to wire the
Ingress + BackendConfig to the Service.

## Notes

- **`cluster_insecure_tls`** — set `true` only when a TLS-inspecting proxy
  (corporate MITM) sits between you and the cluster. It makes the kubernetes/helm
  providers skip cert verification (the endpoint presents the proxy's cert, not the
  GKE cluster CA); the bearer token still authenticates. Leave `false` on a direct
  network. Applies identically in stage 50. Full symptoms + per-tool fixes
  (gcloud/kubectl/curl too) are in
  [Behind a TLS-inspecting proxy (corporate MITM)](../README.md#behind-a-tls-inspecting-proxy-corporate-mitm).
- Image repo/tag come from the console `values.yaml` (or the chart `appVersion`)
  unless you override `image_repository`/`image_tag`.
