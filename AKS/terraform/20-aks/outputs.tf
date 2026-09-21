output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks.name
}

output "resource_group_name" {
  description = "Resource group holding the cluster."
  value       = azurerm_kubernetes_cluster.aks.resource_group_name
}

output "location" {
  description = "Cluster region."
  value       = azurerm_kubernetes_cluster.aks.location
}

output "node_resource_group" {
  description = "Auto-generated resource group holding the cluster's node infrastructure."
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity federation (stage 30 federated credentials)."
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "host" {
  description = "Cluster API server endpoint."
  value       = azurerm_kubernetes_cluster.aks.kube_config[0].host
  sensitive   = true
}

output "client_certificate" {
  description = "Base64-encoded client certificate for the kubernetes/helm providers."
  value       = azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Base64-encoded client key for the kubernetes/helm providers."
  value       = azurerm_kubernetes_cluster.aks.kube_config[0].client_key
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate for the kubernetes/helm providers."
  value       = azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate
  sensitive   = true
}
