# 30-iam — Workload Identity for Vertex AI

Creates the Google service account (GSA) the gateway pod runs as, grants it Vertex
AI access, and binds it to the Kubernetes service account (KSA) that stage 40 will
create. State prefix `30-iam`. Fast (a few seconds).

## Creates

- `google_service_account.gateway` — the gateway GSA (`airs-gw-gateway@<project>...`).
- `google_project_iam_member.vertex_user` — `roles/aiplatform.user` on
  `model_project_id` (defaults to `project_id`; set it for cross-project Vertex).
- `google_service_account_iam_member.workload_identity` —
  `roles/iam.workloadIdentityUser` for member
  `serviceAccount:<project>.svc.id.goog[<namespace>/<ksa_name>]`, so the KSA can
  impersonate the GSA.

## Reads

Nothing via remote state — it derives the WI member from `project_id` + the
`namespace`/`ksa_name` vars, which **must match stage 40**.

## Inputs used (from `../terraform.tfvars`)

`project_id`, `region`, `model_project_id` (optional), `namespace`, `ksa_name`.

## Run

```sh
cd 30-iam
terraform init -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`gsa_email`, `namespace`, `ksa_name`, `model_project_id`, `vertex_project_id`,
`vertex_region`. Stage 40 reads `gsa_email` (for the KSA annotation) and reuses
`namespace`/`ksa_name`.

To configure the Vertex AI provider in the Portkey/AIRS console (auth type
**workload**), read the two values it asks for straight from this stage:

```sh
terraform -chdir=30-iam output -raw vertex_project_id   # Vertex Project ID
terraform -chdir=30-iam output -raw vertex_region       # Vertex Region (e.g. us-central1)
```

`vertex_project_id` is an alias of `model_project_id`; `vertex_region` reflects the
`region` input.

## Notes

- `namespace` and `ksa_name` here **must** equal the same vars in stage 40, or the
  Workload Identity binding won't match the KSA the chart creates and Vertex calls
  will fail with permission errors.
