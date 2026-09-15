locals {
  model_project = var.model_project_id != "" ? var.model_project_id : var.project_id
}

# Google service account the gateway pod impersonates via Workload Identity.
resource "google_service_account" "gateway" {
  project      = var.project_id
  account_id   = var.gsa_name
  display_name = "AIRS AI Gateway (Vertex access)"
}

# Allow the gateway to invoke Vertex AI models (in the model project).
resource "google_project_iam_member" "vertex_user" {
  project = local.model_project
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.gateway.email}"
}

# Bind the KSA (namespace/ksa) to the GSA so the pod can mint GSA tokens.
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.gateway.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.ksa_name}]"
}
