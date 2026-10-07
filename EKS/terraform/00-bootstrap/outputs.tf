output "state_bucket" {
  description = "S3 bucket holding remote state for all later stages. Pass to init via -backend-config=\"bucket=<this>\"."
  value       = aws_s3_bucket.tfstate.id
}

output "state_lock_table" {
  description = "DynamoDB table used for state locking. Pass to init via -backend-config=\"dynamodb_table=<this>\"."
  value       = aws_dynamodb_table.tflock.name
}

output "region" {
  description = "AWS region. Pass to init via -backend-config=\"region=<this>\"."
  value       = var.region
}
