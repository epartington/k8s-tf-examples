variable "region" {
  type        = string
  description = "AWS region for the POV (state bucket, lock table, and all later stages)."
}

variable "state_bucket" {
  type        = string
  description = "Name of the S3 bucket to create for remote Terraform state. Must be globally unique. Reused as the backend bucket by every other stage at init via -backend-config=\"bucket=...\"."
}

variable "state_lock_table" {
  type        = string
  description = "Name of the DynamoDB table to create for Terraform state locking. Reused by every stage at init via -backend-config=\"dynamodb_table=...\"."
  default     = "airs-gw-tflock"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the state resources."
  default = {
    project = "airs-gw"
  }
}
