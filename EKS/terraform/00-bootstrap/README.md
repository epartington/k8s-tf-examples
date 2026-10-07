# 00-bootstrap — remote-state backend (S3 + DynamoDB)

Creates the S3 bucket and DynamoDB lock table that every later stage uses as its
`s3` backend. **Local state** (it can't use the backend it is creating). Run once.

## Creates

- `aws_s3_bucket.tfstate` (+ versioning, SSE, public-access-block, `prevent_destroy`)
  — the remote-state bucket.
- `aws_dynamodb_table.tflock` — `PAY_PER_REQUEST` lock table (hash key `LockID`).

## Reads

Nothing — first stage, local state.

## Inputs used (from `../terraform.tfvars`)

`region`, `state_bucket` (globally unique), `state_lock_table`.

## Run

```sh
cd 00-bootstrap
terraform init
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`state_bucket`, `state_lock_table`, `region` — passed to every later stage's
`init` via `-backend-config`.

## Notes

- The bucket has `prevent_destroy`; `terraform destroy` here will error by design.
  Empty + delete it manually (`aws s3 rb s3://<bucket> --force`) if you really want
  it gone.
- AWS has no API-enablement step (unlike GCP/Azure), so this stage is just state
  infrastructure.
