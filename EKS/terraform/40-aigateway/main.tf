data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = "20-eks.tfstate"
    region         = var.region
    dynamodb_table = var.state_lock_table
  }
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = "30-iam.tfstate"
    region         = var.region
    dynamodb_table = var.state_lock_table
  }
}

locals {
  gateway_role_arn = data.terraform_remote_state.iam.outputs.gateway_role_arn

  # MCP is enabled whenever the server runs in "all" or "mcp" mode. In "all" mode
  # the gateway pod exposes both gateway_port and mcp_port on the same Service, and
  # stage 50 fronts both via the same ALB / WAF web ACL.
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

  # AWS-specific overlay merged on top of the console values.yaml. The IRSA role
  # annotation (role created in stage 30-iam) lets the EKS pod-identity webhook
  # inject AWS credentials automatically — the gateway reaches Bedrock via the
  # default credential chain, no static keys. Plus deterministic gateway/MCP mode
  # and disabling the chart ingress (stage 50 owns ingress).
  aws_overlay = {
    serviceAccount = {
      create = true
      name   = var.ksa_name
      annotations = {
        "eks.amazonaws.com/role-arn" = local.gateway_role_arn
      }
    }

    # Bedrock via IRSA (AWS default credential chain), plus deterministic
    # gateway/MCP mode (overlay wins over the console file).
    environment = {
      data = {
        AWS_REGION  = var.region
        SERVER_MODE = var.server_mode
        MCP_PORT    = tostring(var.mcp_port)
      }
    }

    # ClusterIP: the ALB (stage 50) targets the pods via the Ingress. The chart
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

  # Base = console values.yaml (credentials); overlay = AWS-specific settings.
  # Later entries win, so the overlay overrides the base where they intersect.
  # sensitive() keeps the console values.yaml (registry/Portkey creds) out of
  # plan/apply output — helm_release.values is not sensitive by default.
  values = sensitive([
    file(local.values_file),
    yamlencode(local.aws_overlay),
  ])
}
