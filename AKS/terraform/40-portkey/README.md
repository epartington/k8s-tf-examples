# 40-portkey — namespace + Helm release of the gateway

Deploys the PRISMA AIRS / Portkey `airs-gw` chart into the cluster. State key
`40-portkey.tfstate`. This is the first stage that **talks to the cluster API**
(the kubernetes and helm providers), so this machine's egress IP must be in
`authorized_networks`.

## Prerequisite — the console `values.yaml`

Download the `values.yaml` from the AI Gateway (Portkey) console and save it here:

```text
40-portkey/values.yaml
```

It carries the hybrid credentials (license `PORTKEY_CLIENT_AUTH`, `ORGANISATIONS_TO_SYNC`,
registry pull creds). It is **gitignored — never commit it.** The `values_file` var
defaults to this path. See [values.yaml.example](values.yaml.example) for the shape.
Stage 40 can't `plan`/`apply` (or `validate`) without it — the config uses `file()`.

## Creates

- `kubernetes_namespace.airs` — the `namespace`.
- `helm_release.airs_gw` — the `airs-gw` chart from `chart_repository`, with values
  layered as **[console `values.yaml`, Terraform Azure overlay]** (overlay wins). The
  overlay sets: KSA `serviceAccount.create` + `azure.workload.identity/client-id`
  annotation (Workload Identity), the `azure.workload.identity/use: "true"` pod
  label, `SERVER_MODE`/`MCP_PORT`, `service.type = ClusterIP`, and
  `ingress.enabled = false`.

## Reads

- `20-aks` — `host` + `client_certificate` / `client_key` / `cluster_ca_certificate`
  to configure the providers.
- `30-iam` — `gateway_identity_client_id` for the KSA annotation.

## Inputs used (from `../terraform.tfvars`)

`subscription_id`, `state_resource_group`, `storage_account`, `namespace`,
`ksa_name`, `server_mode`, `mcp_port`, `gateway_port`, optional
`chart_version` / `image_repository` / `image_tag`, and **`cluster_insecure_tls`**
(see Notes).

## Run

```sh
cd 40-portkey
# save values.yaml here first (see above)
terraform init \
  -backend-config="resource_group_name=$(terraform -chdir=../00-bootstrap output -raw resource_group_name)" \
  -backend-config="storage_account_name=$(terraform -chdir=../00-bootstrap output -raw storage_account_name)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

`helm_release` has `wait=true`, so `apply` blocks until the gateway + Redis pods are
Ready (pulls the enterprise image via the console pull secret). Bad image creds
surface here as a pod-start failure.

## Outputs

`namespace`, `release_name`, `service_name`, `service_port`, `mcp_enabled`,
`mcp_service_port`. Stage 50 consumes these to wire the Ingress to the Service.

## Notes

- **`cluster_insecure_tls`** — set `true` only when a TLS-inspecting proxy
  (corporate MITM) sits between you and the cluster. It makes the kubernetes/helm
  providers skip cert verification (the endpoint presents the proxy's cert, not the
  AKS cluster CA); the client certificate still authenticates. Leave `false` on a
  direct network. Applies identically in stage 50. Full symptoms + per-tool fixes
  are in
  [Behind a TLS-inspecting proxy (corporate MITM)](../README.md#behind-a-tls-inspecting-proxy-corporate-mitm).
- **Model auth (open item).** The overlay wires Entra Workload Identity (SA
  annotation + pod label). The chart documents Vertex (`GCP_AUTH_MODE`) and Bedrock
  auth but not an Azure OpenAI auth mode. If the gateway build can't mint an Entra
  token for Azure OpenAI, provide the model **API key** via the console `values.yaml`
  (see `values.yaml.example`) and configure the Azure OpenAI provider in the Portkey
  console with that key. Confirm the working path when the gateway is running.
- **Pod-label key.** The overlay sets `podLabels."azure.workload.identity/use"`;
  confirm the chart renders `podLabels` onto the deployment. If it doesn't, the
  Workload Identity webhook won't inject the token — patch the label onto the
  deployment as a fallback.
- Image repo/tag come from the console `values.yaml` (or the chart `appVersion`)
  unless you override `image_repository`/`image_tag`.
