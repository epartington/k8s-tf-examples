output "network_name" {
  description = "Name of the VPC."
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "Self link of the VPC."
  value       = google_compute_network.vpc.self_link
}

output "subnet_name" {
  description = "Name of the node subnet."
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_self_link" {
  description = "Self link of the node subnet."
  value       = google_compute_subnetwork.subnet.self_link
}

output "pods_range_name" {
  description = "Pods secondary range name, or empty when GKE auto-allocates."
  value       = local.use_explicit_secondary ? var.pods_range_name : ""
}

output "services_range_name" {
  description = "Services secondary range name, or empty when GKE auto-allocates."
  value       = local.use_explicit_secondary ? var.services_range_name : ""
}

output "static_ip_name" {
  description = "Name of the reserved global static IP for the external LB."
  value       = google_compute_global_address.gateway_ip.name
}

output "static_ip_address" {
  description = "The reserved global static IP address (point DNS / nip.io here)."
  value       = google_compute_global_address.gateway_ip.address
}
