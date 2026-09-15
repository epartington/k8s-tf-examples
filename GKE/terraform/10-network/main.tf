locals {
  # Only emit explicit secondary ranges when the operator supplies CIDRs.
  # Otherwise GKE auto-allocates Google-managed pod/service ranges (VPC-native).
  use_explicit_secondary = var.pods_cidr != "" && var.services_cidr != ""

  secondary_ranges = local.use_explicit_secondary ? [
    {
      range_name    = var.pods_range_name
      ip_cidr_range = var.pods_cidr
    },
    {
      range_name    = var.services_range_name
      ip_cidr_range = var.services_cidr
    },
  ] : []
}

# Isolated VPC dedicated to this POV.
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  private_ip_google_access = true

  dynamic "secondary_ip_range" {
    for_each = local.secondary_ranges
    content {
      range_name    = secondary_ip_range.value.range_name
      ip_cidr_range = secondary_ip_range.value.ip_cidr_range
    }
  }
}

# Egress for private nodes: image pulls + reaching api.portkey.ai / albus.portkey.ai.
resource "google_compute_router" "router" {
  name    = "${var.network_name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Allow internal traffic within the VPC (nodes, pods, services).
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.network_name}-allow-internal"
  project = var.project_id
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = compact([
    var.subnet_cidr,
    var.pods_cidr,
    var.services_cidr,
  ])
}

# Allow the private control plane to reach nodes (webhooks, metrics, kubelet).
resource "google_compute_firewall" "allow_master" {
  name    = "${var.network_name}-allow-master"
  project = var.project_id
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "9443", "10250", "8787"]
  }

  source_ranges = [var.master_ipv4_cidr]
}

# Allow Google Front End / health-check ranges to reach node ports behind the LB.
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.network_name}-allow-health-checks"
  project = var.project_id
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
}

# Global static IP for the external Application Load Balancer (stage 50).
resource "google_compute_global_address" "gateway_ip" {
  name    = var.static_ip_name
  project = var.project_id
}
