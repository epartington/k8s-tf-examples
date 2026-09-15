output "namespace" {
  description = "Namespace the gateway runs in."
  value       = kubernetes_namespace.airs.metadata[0].name
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.airs_gw.name
}

output "service_name" {
  description = "Gateway ClusterIP Service name (chart fullname = release name). Target for the stage 50 Ingress."
  value       = var.helm_release_name
}

output "service_port" {
  description = "Gateway Service port."
  value       = var.gateway_port
}

output "backend_config_name" {
  description = "BackendConfig name referenced by the Service annotation (created in stage 50-ingress)."
  value       = var.backend_config_name
}
