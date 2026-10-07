data "terraform_remote_state" "network" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group
    storage_account_name = var.storage_account
    container_name       = var.container_name
    key                  = "10-network.tfstate"
  }
}

locals {
  net = data.terraform_remote_state.network.outputs

  # Nodes egress via the NAT Gateway, so its public IP must be in the API server
  # authorized ranges or node bootstrap can't reach the public control plane
  # (CSE exit 51). With outbound_type = userAssignedNATGateway, AKS does not add
  # it automatically, so we append it to the operator-supplied ranges.
  authorized_ip_ranges = distinct(concat(
    var.authorized_networks,
    ["${local.net.nat_public_ip_address}/32"],
  ))
}

# Private-node AKS cluster: public API server locked by authorized IP ranges,
# OIDC issuer + Workload Identity enabled, egress via the 10-network NAT Gateway.
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = local.net.location
  resource_group_name = local.net.resource_group_name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version != "" ? var.kubernetes_version : null
  tags                = var.tags

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name            = "system"
    node_count      = var.node_count
    vm_size         = var.vm_size
    os_disk_size_gb = var.node_disk_size_gb
    vnet_subnet_id  = local.net.aks_subnet_id
  }

  # Control-plane identity. With SystemAssigned, AKS also auto-creates a
  # system-assigned kubelet (node) identity that is minimal by default — it only
  # gains AcrPull when attached to an ACR. This is the Azure parallel of GKE's
  # "dedicated least-privilege node SA": AKS nodes do NOT inherit a broad default
  # identity (unlike GCE's default Compute SA), so no extra hardening is needed here.
  identity {
    type = "SystemAssigned"
  }

  # Azure CNI overlay; egress bound to the pre-associated user NAT Gateway.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    outbound_type       = "userAssignedNATGateway"
  }

  # Public API server endpoint restricted to the operator/CI egress CIDRs so
  # stages 40/50 (kubernetes/helm providers) and kubectl can connect.
  api_server_access_profile {
    authorized_ip_ranges = local.authorized_ip_ranges
  }
}
