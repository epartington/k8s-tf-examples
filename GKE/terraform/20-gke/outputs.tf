output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.gke.name
}

output "location" {
  description = "Cluster location (zone for the zonal POV cluster)."
  value       = google_container_cluster.gke.location
}

output "endpoint" {
  description = "Public control-plane endpoint."
  value       = google_container_cluster.gke.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = google_container_cluster.gke.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_pool" {
  description = "Workload Identity pool (<project>.svc.id.goog)."
  value       = google_container_cluster.gke.workload_identity_config[0].workload_pool
}
