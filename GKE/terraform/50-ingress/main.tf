data "terraform_remote_state" "gke" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "20-gke"
  }
}

data "terraform_remote_state" "network" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "10-network"
  }
}

data "terraform_remote_state" "portkey" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "40-portkey"
  }
}

locals {
  static_ip_name    = data.terraform_remote_state.network.outputs.static_ip_name
  static_ip_address = data.terraform_remote_state.network.outputs.static_ip_address

  namespace           = data.terraform_remote_state.portkey.outputs.namespace
  service_name        = data.terraform_remote_state.portkey.outputs.service_name
  service_port        = data.terraform_remote_state.portkey.outputs.service_port
  backend_config_name = data.terraform_remote_state.portkey.outputs.backend_config_name

  # MCP: only front it when stage 40 actually enabled it (server_mode all/mcp).
  mcp_enabled = data.terraform_remote_state.portkey.outputs.mcp_enabled
  mcp_port    = data.terraform_remote_state.portkey.outputs.mcp_service_port

  # Managed cert needs a real FQDN. Fall back to nip.io pointing at the LB IP.
  domain = var.domain != "" ? var.domain : "${local.static_ip_address}.nip.io"

  # MCP gets its own hostname on the SAME cert/IP/Cloud Armor. With the nip.io
  # fallback, "mcp.<ip>.nip.io" resolves to the same LB IP automatically.
  mcp_domain = var.mcp_domain != "" ? var.mcp_domain : "mcp.${local.domain}"

  # Domains on the managed cert: add the MCP SAN only when MCP is enabled.
  cert_domains = local.mcp_enabled ? [local.domain, local.mcp_domain] : [local.domain]
}

# Cloud Armor: allow only the POV source ranges, deny everything else.
resource "google_compute_security_policy" "armor" {
  name    = var.security_policy_name
  project = var.project_id

  dynamic "rule" {
    for_each = length(var.allowed_source_ranges) > 0 ? [1] : []
    content {
      action   = "allow"
      priority = 1000
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = var.allowed_source_ranges
        }
      }
      description = "Allow POV source ranges"
    }
  }

  # Default rule (lowest priority) denies all other sources.
  rule {
    action   = "deny(403)"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default deny"
  }
}

# Google-managed TLS cert, referenced by the Ingress as a pre-shared cert.
resource "google_compute_managed_ssl_certificate" "cert" {
  name    = var.managed_cert_name
  project = var.project_id

  managed {
    domains = local.cert_domains
  }
}

# --- IAP scaffold (off by default) ---

resource "google_iap_brand" "brand" {
  count = var.iap_enabled ? 1 : 0

  provider          = google-beta
  project           = var.project_id
  support_email     = var.iap_support_email
  application_title = "AIRS AI Gateway"
}

resource "google_iap_client" "client" {
  count = var.iap_enabled ? 1 : 0

  provider     = google-beta
  display_name = "AIRS AI Gateway IAP"
  brand        = google_iap_brand.brand[0].name
}

resource "kubernetes_secret" "iap_oauth" {
  count = var.iap_enabled ? 1 : 0

  metadata {
    name      = var.iap_oauth_secret_name
    namespace = local.namespace
  }

  data = {
    client_id     = google_iap_client.client[0].client_id
    client_secret = google_iap_client.client[0].secret
  }
}

# BackendConfig: attach Cloud Armor, define the health check, gate IAP.
resource "kubernetes_manifest" "backend_config" {
  manifest = {
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = local.backend_config_name
      namespace = local.namespace
    }
    spec = merge(
      {
        securityPolicy = {
          name = google_compute_security_policy.armor.name
        }
        healthCheck = {
          type        = "HTTP"
          requestPath = var.health_check_path
          port        = var.gateway_port
        }
      },
      var.iap_enabled ? {
        iap = {
          enabled = true
          oauthclientCredentials = {
            secretName = var.iap_oauth_secret_name
          }
        }
      } : {}
    )
  }
}

# Global external HTTPS Application Load Balancer fronting the gateway.
resource "kubernetes_ingress_v1" "gateway" {
  metadata {
    name      = var.ingress_name
    namespace = local.namespace
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = local.static_ip_name
      "ingress.gcp.kubernetes.io/pre-shared-cert"   = google_compute_managed_ssl_certificate.cert.name
      "kubernetes.io/ingress.allow-http"            = "false"
    }
  }

  spec {
    # Gateway on the primary domain (and any unmatched host).
    default_backend {
      service {
        name = local.service_name
        port {
          number = local.service_port
        }
      }
    }

    # MCP on its own hostname, same Service/pod (mcp_port), same ALB, same
    # Cloud Armor + cert. "/*" forwards every path so we don't depend on the
    # MCP server's internal path layout.
    dynamic "rule" {
      for_each = local.mcp_enabled ? [1] : []
      content {
        host = local.mcp_domain
        http {
          path {
            path      = "/*"
            path_type = "ImplementationSpecific"
            backend {
              service {
                name = local.service_name
                port {
                  number = local.mcp_port
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.backend_config]
}
