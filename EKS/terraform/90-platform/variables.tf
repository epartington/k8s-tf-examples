variable "region" {
  type        = string
  description = "AWS region (to read the other stages' remote state)."
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket holding remote state for all stages."
}

variable "state_lock_table" {
  type        = string
  description = "DynamoDB table used for state locking."
  default     = "airs-gw-tflock"
}
