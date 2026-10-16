terraform {
  required_version = ">= 1.5.0"

  # Read-only aggregation stage: it only reads the other stages' remote state and
  # re-exports a curated, stable output set. No providers/resources — just the
  # built-in terraform_remote_state data source and outputs.
  #
  # bucket, dynamodb_table, and region are passed at init via -backend-config.
  backend "s3" {
    key = "90-platform.tfstate"
  }
}
