data "terraform_remote_state" "aks" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group
    storage_account_name = var.storage_account
    container_name       = var.container_name
    key                  = "20-aks.tfstate"
  }
}

data "terraform_remote_state" "iam" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group
    storage_account_name = var.storage_account
    container_name       = var.container_name
    key                  = "30-iam.tfstate"
  }
}

locals {
  gateway_client_id = data.terraform_remote_state.iam.outputs.gateway_identity_client_id

  # MCP is enabled whenever the server runs in "all" or "mcp" mode. In "all" mode
  # the gateway pod exposes both gateway_port and mcp_port on the same Service, and
  # stage 50 fronts both via the same Application Gateway / WAF policy.
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

  # Azure-specific overlay merged on top of the console values.yaml. These are the
  # bits the console file cannot know: the Workload Identity SA annotation + pod
  # label (the managed identity is created in stage 30-iam), deterministic
  # gateway/MCP mode, and disabling the chart ingress (stage 50 owns ingress).
  azure_overlay = {
    serviceAccount = {
      create = true
      name   = var.ksa_name
      annotations = {
        "azure.workload.identity/client-id" = local.gateway_client_id
      }
    }

    # Required for the Workload Identity webhook to project the token into the pod.
    podLabels = {
      "azure.workload.identity/use" = "true"
    }

    # Deterministic gateway/MCP mode (overlay wins over the console file).
    environment = {
      data = {
        SERVER_MODE = var.server_mode
        MCP_PORT    = tostring(var.mcp_port)
      }
    }

    # ClusterIP: AGIC in stage 50 routes to the Service via the Ingress. The chart
    # adds the MCP port to this same Service automatically when SERVER_MODE is
    # "all"/"mcp", so no extra port entry is needed here.
    service = {
      type = "ClusterIP"
      port = var.gateway_port
    }

    # Image overrides merged onto the chart's images block. gatewayImage honours
    # the image_repository/image_tag convenience vars; image_overrides can set any
    # chart image (gatewayImage, dataserviceImage, redisImage, ...) and wins on
    # intersection, so a newer image can run on top of the pinned chart version.
    # Empty maps merge harmlessly over the chart defaults.
    images = merge(
      { gatewayImage = local.gateway_image },
      var.image_overrides,
    )

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

  # Base = console values.yaml (credentials); overlay = Azure-specific settings.
  # Later entries win, so the overlay overrides the base where they intersect.
  # sensitive() keeps the console values.yaml (registry/Portkey creds) out of
  # plan/apply output — helm_release.values is not sensitive by default.
  values = sensitive([
    file(local.values_file),
    yamlencode(local.azure_overlay),
  ])
}
