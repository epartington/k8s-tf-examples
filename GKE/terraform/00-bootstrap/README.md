# 00-bootstrap — remote-state backend + project APIs

First stage. Creates the GCS bucket that every later stage uses for remote state,
and enables the Google APIs the rest of the project needs. **Uses LOCAL state**
(it can't use the remote bucket — it's creating it).

## Creates

- `google_storage_bucket.tfstate` — versioned, uniform-access bucket named after
  `state_bucket`. Holds the remote state for stages 10–50 (one `prefix` each).
- `google_project_service.apis` — enables: `compute`, `container`, `iam`,
  `iamcredentials`, `storage`, `aiplatform`, `certificatemanager`, `iap`.

## Reads

Nothing — this is the root of the chain.

## Inputs used (from `../terraform.tfvars`)

`project_id`, `region`, `state_bucket`. (`state_bucket` must be globally unique and
must match the value every later stage inits against.)

## Run

```sh
cd 00-bootstrap
terraform init                                   # local state, no backend config
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

The many "Value for undeclared variable" warnings are expected: the shared
`terraform.tfvars` carries inputs for all stages, and each stage ignores the ones
it doesn't declare.

## Outputs

- `state_bucket` — the bucket name; feed it to every later stage's `init`
  (the other READMEs use `terraform -chdir=../00-bootstrap output -raw state_bucket`).
- `enabled_apis` — the list of APIs enabled.

## Notes

- The bucket carries `prevent_destroy`. To tear the project down fully you must
  empty and remove it manually (see the top-level [README](../README.md#teardown)).
