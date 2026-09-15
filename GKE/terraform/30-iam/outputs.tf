output "gsa_email" {
  description = "Email of the gateway GSA (used for the KSA annotation in stage 40)."
  value       = google_service_account.gateway.email
}

output "namespace" {
  description = "Namespace the WI binding targets."
  value       = var.namespace
}

output "ksa_name" {
  description = "KSA name the WI binding targets."
  value       = var.ksa_name
}

output "model_project_id" {
  description = "Project granted roles/aiplatform.user."
  value       = local.model_project
}
