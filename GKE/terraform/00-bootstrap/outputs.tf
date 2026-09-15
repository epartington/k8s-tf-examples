output "state_bucket" {
  description = "GCS bucket holding remote state for all later stages. Pass to `terraform init -backend-config=\"bucket=<this>\"`."
  value       = google_storage_bucket.tfstate.name
}

output "enabled_apis" {
  description = "APIs enabled on the project."
  value       = sort([for s in google_project_service.apis : s.service])
}
