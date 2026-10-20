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

  # --- Datadog OTEL (optional) — ports the proven EKS config from cicd-k8s-ai-gw ---
  # The gateway pushes OTLP to a Datadog Agent SIDECAR on localhost:4318, which forwards
  # to Datadog. The sidecar is required because the gateway targets loopback (same-pod).
  # Two exporters: OTEL_PUSH_* = aggregated analytics; EXPERIMENTAL_GEN_AI_OTEL_* =
  # per-request GenAI spans (APM + AI Observability). See datadog/README.md.
  # Split into two homogeneous lists (plain value vs valueFrom) so the gated conditional
  # type-unifies; concat keeps DD_API_KEY FIRST so k8s $(DD_API_KEY) interpolation in the
  # HEADERS var resolves (a var can only reference env defined earlier in the list).
  dd_extra_env = concat(
    var.enable_datadog_otel ? [
      { name = "DD_API_KEY", valueFrom = { secretKeyRef = { name = var.datadog_secret_name, key = "dd_api_key" } } },
    ] : [],
    var.enable_datadog_otel ? [
      { name = "OTEL_PUSH_ENABLED", value = "true" },
      { name = "OTEL_ENDPOINT", value = var.otel_endpoint },
      { name = "OTEL_SERVICE_NAME", value = var.otel_service_name },
      { name = "EXPERIMENTAL_GEN_AI_OTEL_TRACES_ENABLED", value = "true" },
      { name = "OTEL_EXPORTER_OTLP_PROTOCOL", value = "http/json" },
      # BASE url — the gateway appends /v1/traces itself (don't add it → /v1/traces/v1/traces 404).
      { name = "EXPERIMENTAL_GEN_AI_OTEL_EXPORTER_OTLP_ENDPOINT", value = var.otel_endpoint },
      # No dd-otlp-source=llmobs header; the Agent derives AI Observability from gen_ai.* semconv
      # on its own and keeps APM inferred services. $(DD_API_KEY) is inert via the sidecar.
      { name = "EXPERIMENTAL_GEN_AI_OTEL_EXPORTER_OTLP_HEADERS", value = "dd-api-key=$(DD_API_KEY)" },
      { name = "EXPERIMENTAL_GEN_AI_OTEL_RESOURCE_ATTRIBUTES", value = "deployment.environment.name=${var.datadog_env},deployment.environment=${var.datadog_env}" },
    ] : [],
  )

  dd_sidecars = var.enable_datadog_otel ? [
    {
      name            = "datadog-agent"
      image           = var.datadog_agent_image
      imagePullPolicy = "IfNotPresent"
      ports = [
        { name = "otlp-http", containerPort = 4318 },
        { name = "otlp-grpc", containerPort = 4317 },
      ]
      env = [
        { name = "DD_API_KEY", valueFrom = { secretKeyRef = { name = var.datadog_secret_name, key = "dd_api_key" } } },
        { name = "DD_SITE", value = var.datadog_site },
        { name = "DD_SERVICE", value = var.datadog_service },
        { name = "DD_ENV", value = var.datadog_env },
        { name = "DD_APM_ENABLED", value = "true" },
        { name = "DD_OTLP_CONFIG_RECEIVER_PROTOCOLS_HTTP_ENDPOINT", value = "0.0.0.0:4318" },
        { name = "DD_OTLP_CONFIG_RECEIVER_PROTOCOLS_GRPC_ENDPOINT", value = "0.0.0.0:4317" },
        { name = "DD_HOSTNAME", valueFrom = { fieldRef = { fieldPath = "metadata.name" } } },
      ]
      securityContext = { allowPrivilegeEscalation = false }
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
  ] : []

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

    # Deterministic gateway/MCP mode (overlay wins over the console file). When Datadog
    # is on, TRUSTED_CUSTOM_HOSTS must allowlist localhost or the gateway's SSRF guard
    # blocks the OTLP push to the loopback sidecar ("TypeError: fetch failed"). Host-only
    # match REPLACES the built-in defaults, so include every host you need.
    environment = {
      data = merge(
        {
          SERVER_MODE = var.server_mode
          MCP_PORT    = tostring(var.mcp_port)
        },
        # Advertise the external https base URL in MCP OAuth metadata when behind a TLS-terminating
        # proxy (App Gateway); without it the server derives http:// from the forwarded request.
        var.mcp_gateway_base_url != "" ? { MCP_GATEWAY_BASE_URL = var.mcp_gateway_base_url } : {},
        var.enable_datadog_otel ? { TRUSTED_CUSTOM_HOSTS = var.otel_trusted_custom_hosts } : {},
      )
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

    # Optional Datadog OTEL: extra gateway env + the DD Agent sidecar. Empty lists
    # when disabled, which the chart renders as nothing.
    extraEnv = local.dd_extra_env
    sidecars = local.dd_sidecars
  }
}

resource "kubernetes_namespace" "airs" {
  metadata {
    name = var.namespace
  }
}

# Datadog API key cluster Secret for the Agent sidecar + gateway header (optional).
# Created from the gitignored terraform.tfvars.
resource "kubernetes_secret" "datadog" {
  count = var.enable_datadog_otel ? 1 : 0

  metadata {
    name      = var.datadog_secret_name
    namespace = kubernetes_namespace.airs.metadata[0].name
  }
  data = {
    "dd_api_key" = var.datadog_api_key
  }
  type = "Opaque"
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

  # Ensure the Datadog secret exists before the pod (sidecar) starts.
  depends_on = [kubernetes_secret.datadog]
}
