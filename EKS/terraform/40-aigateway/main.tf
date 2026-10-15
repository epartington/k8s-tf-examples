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

  # --- Datadog OTEL (optional) — ports the proven EKS config from cicd-k8s-ai-gw ---
  # The gateway pushes OTLP to a Datadog Agent SIDECAR on localhost:4318, which forwards
  # to Datadog. Mirrors the ECS Fargate target (DD Agent as a per-task sidecar; no
  # node/DaemonSet on Fargate). Two exporters: OTEL_PUSH_* = aggregated analytics only;
  # EXPERIMENTAL_GEN_AI_OTEL_* = per-request GenAI spans (APM + AI Observability). See
  # datadog/README.md and datadog/EXTERNAL-SETUP.md.
  # Split into two homogeneous lists (plain value vs valueFrom) so the gated conditional
  # type-unifies; concat keeps DD_API_KEY FIRST so k8s $(DD_API_KEY) interpolation in the
  # HEADERS var resolves (a var can only reference env defined earlier in the list).
  dd_extra_env = concat(
    # DD_API_KEY (valueFrom) — must come before the HEADERS var below.
    var.enable_datadog_otel ? [
      { name = "DD_API_KEY", valueFrom = { secretKeyRef = { name = var.datadog_secret_name, key = "dd_api_key" } } },
    ] : [],
    var.enable_datadog_otel ? [
      # Aggregated-analytics push + the single service name everything folds into.
      { name = "OTEL_PUSH_ENABLED", value = "true" },
      { name = "OTEL_ENDPOINT", value = var.otel_endpoint },
      { name = "OTEL_SERVICE_NAME", value = var.otel_service_name },
      # Per-request GenAI spans (the real traces); OTEL_PUSH_* alone does NOT emit these.
      { name = "EXPERIMENTAL_GEN_AI_OTEL_TRACES_ENABLED", value = "true" },
      # Wire format for the analytics push only (GenAI exporter is hardcoded http/json).
      { name = "OTEL_EXPORTER_OTLP_PROTOCOL", value = "http/json" },
      # BASE url — the gateway appends /v1/traces itself (don't add it → /v1/traces/v1/traces 404).
      { name = "EXPERIMENTAL_GEN_AI_OTEL_EXPORTER_OTLP_ENDPOINT", value = var.otel_endpoint },
      # No dd-otlp-source=llmobs header (that diverts from APM inferred services); the Agent
      # derives AI Observability from the gen_ai.* semconv on its own. $(DD_API_KEY) is inert
      # via the sidecar but kept so flipping ENDPOINT to the direct intake later just works.
      { name = "EXPERIMENTAL_GEN_AI_OTEL_EXPORTER_OTLP_HEADERS", value = "dd-api-key=$(DD_API_KEY)" },
      # env tags only (no service.name — the bundle hardcodes service.name=portkey, first-wins
      # via the Agent). Send both semconv forms; DD maps the deprecated one to `env` most reliably.
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
        # OTLP/HTTP + gRPC receivers the gateway targets at localhost:4318/4317.
        { name = "DD_OTLP_CONFIG_RECEIVER_PROTOCOLS_HTTP_ENDPOINT", value = "0.0.0.0:4318" },
        { name = "DD_OTLP_CONFIG_RECEIVER_PROTOCOLS_GRPC_ENDPOINT", value = "0.0.0.0:4317" },
        # Sidecar has no node/kubelet access; pin the hostname to the pod name.
        { name = "DD_HOSTNAME", valueFrom = { fieldRef = { fieldPath = "metadata.name" } } },
      ]
      # Agent needs a writable rootfs; the chart's readOnlyRootFilesystem applies to the
      # gateway container only, so just disable privilege escalation here.
      securityContext = { allowPrivilegeEscalation = false }
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
  ] : []

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
    # gateway/MCP mode (overlay wins over the console file). When Datadog is on,
    # TRUSTED_CUSTOM_HOSTS must allowlist localhost or the gateway's SSRF guard blocks
    # the OTLP push to the loopback sidecar ("TypeError: fetch failed"). Host-only match
    # REPLACES the built-in defaults, so include every host you need.
    environment = {
      data = merge(
        {
          AWS_REGION  = var.region
          SERVER_MODE = var.server_mode
          MCP_PORT    = tostring(var.mcp_port)
        },
        var.enable_datadog_otel ? { TRUSTED_CUSTOM_HOSTS = var.otel_trusted_custom_hosts } : {},
      )
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
# Created from the gitignored terraform.tfvars. (On ECS Fargate this becomes a task
# secret from Secrets Manager / SSM.)
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

  # Base = console values.yaml (credentials); overlay = AWS-specific settings.
  # Later entries win, so the overlay overrides the base where they intersect.
  # sensitive() keeps the console values.yaml (registry/Portkey creds) out of
  # plan/apply output — helm_release.values is not sensitive by default.
  values = sensitive([
    file(local.values_file),
    yamlencode(local.aws_overlay),
  ])

  # Ensure the Datadog secret exists before the pod (sidecar) starts.
  depends_on = [kubernetes_secret.datadog]
}
