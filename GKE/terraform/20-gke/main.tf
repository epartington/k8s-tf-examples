data "terraform_remote_state" "network" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "10-network"
  }
}

locals {
  location = var.zone != "" ? var.zone : "${var.region}-a"

  net           = data.terraform_remote_state.network.outputs
  pods_range    = local.net.pods_range_name
  svc_range     = local.net.services_range_name
  use_auto_cidr = local.pods_range == "" || local.svc_range == ""
}

resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  project  = var.project_id
  location = local.location

  network    = local.net.network_self_link
  subnetwork = local.net.subnet_self_link

  # Manage nodes only through the separate node pool below.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }

  # VPC-native. When explicit ranges were not created in 10-network, leave the
  # range names unset so GKE auto-allocates Google-managed pod/service ranges.
  ip_allocation_policy {
    cluster_secondary_range_name  = local.use_auto_cidr ? null : local.pods_range
    services_secondary_range_name = local.use_auto_cidr ? null : local.svc_range
  }

  # Private nodes; keep a public control-plane endpoint locked by authorized networks.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value
        display_name = "authorized-${cidr_blocks.key}"
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
  }

  deletion_protection = false
}

resource "google_container_node_pool" "primary" {
  name     = "${var.cluster_name}-np"
  project  = var.project_id
  location = local.location
  cluster  = google_container_cluster.gke.name

  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = var.node_disk_type

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    # Required for Workload Identity on the nodes.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      app = "airs-gw"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
