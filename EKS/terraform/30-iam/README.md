# 30-iam — IRSA roles (gateway + LB controller)

Creates the IAM roles the gateway pod and the AWS Load Balancer Controller assume
via IRSA (IAM Roles for Service Accounts), federated to the cluster OIDC provider.
State key `30-iam.tfstate`. Fast (a few seconds).

## Creates

- `aws_iam_role.gateway` + `aws_iam_role_policy.gateway_bedrock` — the gateway pod
  identity (trust condition `sub = system:serviceaccount:<namespace>:<ksa_name>`)
  with a **Bedrock invoke** policy (`bedrock:InvokeModel*`, `ListFoundationModels`,
  `GetFoundationModel`). This is the `roles/aiplatform.user` analog.
- `aws_iam_role.lb_controller` + `aws_iam_policy.lb_controller` (from
  `lb-controller-policy.json`) — the AWS Load Balancer Controller identity (the AGIC
  analog), consumed by the Helm install in stage 50.

## Reads

- `20-eks` — `oidc_provider_arn`, `oidc_provider_url` for the IRSA trust policies.

## Inputs used (from `../terraform.tfvars`)

`region`, `state_bucket`, `cluster_name`, `namespace`, `ksa_name` (**must match
stage 40**), `bedrock_model_arns`, `lb_controller_namespace`, `lb_controller_sa_name`.

## Run

```sh
cd 30-iam
terraform init \
  -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)" \
  -backend-config="dynamodb_table=$(terraform -chdir=../00-bootstrap output -raw state_lock_table)" \
  -backend-config="region=$(terraform -chdir=../00-bootstrap output -raw region)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`gateway_role_arn` (KSA annotation in stage 40), `namespace`, `ksa_name`,
`lb_controller_role_arn`, `lb_controller_namespace`, `lb_controller_sa_name`.

## Notes

- **`namespace`/`ksa_name` here must equal stage 40's**, or the IRSA trust condition
  won't match the KSA the chart creates and Bedrock calls fail with AccessDenied.
- **Bedrock model access is a prerequisite**, not automatable here: enable model
  access once per region in the Bedrock console (the `aiplatform.googleapis.com`
  enablement analog). The IAM policy only grants *permission* to invoke.
- `bedrock_model_arns` defaults to `["*"]` (POV); scope to specific model ARNs for
  production.
- The LB controller policy mirrors the official AWS policy; tighten if desired.
