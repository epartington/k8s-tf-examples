# 40-aigateway — namespace + Helm release of the gateway

Deploys the PRISMA AIRS / Portkey `airs-gw` chart into the cluster. State key
`40-aigateway.tfstate`. First stage that **talks to the cluster API** (the
kubernetes and helm providers), so this machine's egress IP must be in
`authorized_networks`.

## Prerequisite — the console `values.yaml`

Download the `values.yaml` from the AI Gateway (Portkey) console and save it here:

```text
40-aigateway/values.yaml
```

It carries the hybrid credentials (license `PORTKEY_CLIENT_AUTH`,
`ORGANISATIONS_TO_SYNC`, registry pull creds). It is **gitignored — never commit
it.** The `values_file` var defaults to this path. See
[values.yaml.example](values.yaml.example) for the shape. Stage 40 can't
`plan`/`apply` (or `validate`) without it — the config uses `file()`.

## Creates

- `kubernetes_namespace.airs` — the `namespace`.
- `helm_release.airs_gw` — the `airs-gw` chart, values layered as **[console
  `values.yaml`, Terraform AWS overlay]** (overlay wins). The overlay sets: the KSA
  with the `eks.amazonaws.com/role-arn` **IRSA** annotation, `AWS_REGION` +
  `SERVER_MODE`/`MCP_PORT` env, `service.type = ClusterIP`, and
  `ingress.enabled = false`.

## Reads

- `20-eks` — `cluster_endpoint` + `cluster_ca_certificate` + `cluster_name` to
  configure the providers (token via `aws_eks_cluster_auth`).
- `30-iam` — `gateway_role_arn` for the KSA annotation.

## Inputs used (from `../terraform.tfvars`)

`region`, `state_bucket`, `namespace`, `ksa_name`, `server_mode`, `mcp_port`,
`gateway_port`, `chart_version` (pinned to `1.2.0` by default), optional
`image_repository` / `image_tag` / `image_overrides`, and **`cluster_insecure_tls`**
(see Notes).

## Run

```sh
cd 40-aigateway
# save values.yaml here first (see above)
terraform init \
  -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)" \
  -backend-config="dynamodb_table=$(terraform -chdir=../00-bootstrap output -raw state_lock_table)" \
  -backend-config="region=$(terraform -chdir=../00-bootstrap output -raw region)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

`helm_release` has `wait=true`, so `apply` blocks until the gateway + Redis pods are
Ready.

## Outputs

`namespace`, `release_name`, `service_name`, `service_port`, `mcp_enabled`,
`mcp_service_port`. Stage 50 consumes these to wire the Ingress to the Service.

## Notes

- **`cluster_insecure_tls`** — set `true` only when a TLS-inspecting proxy
  (corporate MITM) sits between you and the cluster; the providers then skip cert
  verification (the token still authenticates). Applies identically in stage 50.
- **Model auth.** Bedrock uses the AWS default credential chain via IRSA — the
  stage-30 role is injected by the EKS pod-identity webhook (no static keys).
  Configure the Bedrock provider in the Portkey console with assumed-role/default
  credentials. If IRSA is unavailable, static keys can be supplied via the console
  `values.yaml` (see `values.yaml.example`).
- **Chart version** is pinned to `1.2.0` (`chart_version` default); set
  `chart_version = ""` for latest. `image_overrides` (keyed by chart image name)
  pins any chart image on top of the pinned chart, e.g.
  `image_overrides = { gatewayImage = { tag = "2.22.0" } }`.
- **Secrets in output.** The `helm_release` values are wrapped in `sensitive()`
  (parity with GKE/AKS) so credentials aren't echoed into plan/apply output.
