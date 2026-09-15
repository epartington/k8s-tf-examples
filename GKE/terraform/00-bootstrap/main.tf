# Enable the project APIs the rest of the stages depend on.
resource "google_project_service" "apis" {
  for_each = toset(var.activate_apis)

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = var.disable_services_on_destroy
}

# Remote-state bucket used as the gcs backend by stages 10-50.
resource "google_storage_bucket" "tfstate" {
  name     = var.state_bucket
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.apis]
}
