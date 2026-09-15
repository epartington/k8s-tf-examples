data "terraform_remote_state" "gke" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "20-gke"
  }
}

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "30-iam"
  }
}

locals {
  gsa_email = data.terraform_remote_state.iam.outputs.gsa_email

  # MCP is enabled whenever the server runs in "all" or "mcp" mode. In "all"
  # mode the gateway pod exposes both gateway_port and mcp_port on the same
  # Service, and stage 50 fronts both via the same ALB/Cloud Armor.
  mcp_enabled = contains(["all", "mcp"], var.server_mode)

  # values.yaml downloaded from the AI Gateway console (carries credentials).
  # Defaults to this stage directory so dropping the file in place just works.
  values_file = var.values_file != "" ? var.values_file : "${path.module}/values.yaml"

  # Only override the image repo/tag when explicitly set; otherwise let the
  # console values.yaml / chart drive the version.
  gateway_image = merge(
    var.image_repository != "" ? { repository = var.image_repository } : {},
    var.image_tag != "" ? { tag = var.image_tag } : {},
  )

  # GCP-specific overlay merged on top of the console values.yaml. These are the
  # bits the console file cannot know: the Workload Identity SA annotation (the
  # GSA is created in stage 30-iam), container-native LB annotations for the
  # stage-50 ingress, Vertex workload auth mode, and disabling the chart ingress.
  gcp_overlay = {
    serviceAccount = {
      create = true
      name   = var.ksa_name
      annotations = {
        "iam.gke.io/gcp-service-account" = local.gsa_email
      }
    }

    # Vertex AI via GKE Workload Identity, plus deterministic gateway/MCP mode
    # (overlay wins, so the POV controls these regardless of the console file).
    environment = {
      data = {
        GCP_AUTH_MODE = "workload"
        SERVER_MODE   = var.server_mode
        MCP_PORT      = tostring(var.mcp_port)
      }
    }

    # ClusterIP + NEG so the external ALB in stage 50 targets pods directly.
    # The chart adds the MCP port (mcp_port) to this same Service automatically
    # when SERVER_MODE is "all"/"mcp", so no extra port entry is needed here.
    # The BackendConfig itself is created in stage 50; the "default" mapping
    # applies it (Cloud Armor + health check) to BOTH the gateway and MCP ports.
    service = {
      type = "ClusterIP"
      port = var.gateway_port
      annotations = {
        "cloud.google.com/neg"            = jsonencode({ ingress = true })
        "cloud.google.com/backend-config" = jsonencode({ default = var.backend_config_name })
      }
    }

    # Optional image override (empty map merges harmlessly over the base values).
    images = {
      gatewayImage = local.gateway_image
    }

    # Ingress is managed in stage 50-ingress, not by the chart.
    ingress = { enabled = false }
  }
}

resource "kubernetes_namespace" "airs" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "airs_gw" {
  name       = var.helm_release_name
  repository = var.chart_repository
  chart      = var.chart_name
  version    = var.chart_version != "" ? var.chart_version : null
  namespace  = kubernetes_namespace.airs.metadata[0].name

  # Pulled from the official airs-gw Helm repo; wait for rollout.
  wait    = true
  timeout = 600

  # Base = console values.yaml (credentials); overlay = GCP-specific settings.
  # Later entries win, so the overlay overrides the base where they intersect.
  values = [
    file(local.values_file),
    yamlencode(local.gcp_overlay),
  ]
}
