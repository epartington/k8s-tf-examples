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

# Portkey control-plane credentials, read from Secret Manager at apply time.
data "google_secret_manager_secret_version" "client_auth" {
  project = var.project_id
  secret  = var.sm_aigw_client_auth
}

data "google_secret_manager_secret_version" "org_id" {
  project = var.project_id
  secret  = var.sm_organisations_to_sync
}

data "google_secret_manager_secret_version" "docker_user" {
  project = var.project_id
  secret  = var.sm_docker_username
}

data "google_secret_manager_secret_version" "docker_pass" {
  project = var.project_id
  secret  = var.sm_docker_password
}

locals {
  gsa_email = data.terraform_remote_state.iam.outputs.gsa_email

  # dockerconfigjson for pulling the enterprise gateway image.
  dockerconfig = jsonencode({
    auths = {
      (var.registry_server) = {
        username = data.google_secret_manager_secret_version.docker_user.secret_data
        password = data.google_secret_manager_secret_version.docker_pass.secret_data
        auth = base64encode(
          "${data.google_secret_manager_secret_version.docker_user.secret_data}:${data.google_secret_manager_secret_version.docker_pass.secret_data}"
        )
      }
    }
  })
}

resource "kubernetes_namespace" "airs" {
  metadata {
    name = var.namespace
  }
}

# Sensitive control-plane env, sourced from Secret Manager. The chart references
# these keys via environment.existingSecret + secretKeys (explicit mode).
resource "kubernetes_secret" "env" {
  metadata {
    name      = var.env_secret_name
    namespace = kubernetes_namespace.airs.metadata[0].name
  }

  data = {
    PORTKEY_CLIENT_AUTH   = data.google_secret_manager_secret_version.client_auth.secret_data
    ORGANISATIONS_TO_SYNC = data.google_secret_manager_secret_version.org_id.secret_data
  }

  type = "Opaque"
}

# Registry pull secret for the enterprise gateway image.
resource "kubernetes_secret" "registry" {
  metadata {
    name      = var.pull_secret_name
    namespace = kubernetes_namespace.airs.metadata[0].name
  }

  data = {
    ".dockerconfigjson" = local.dockerconfig
  }

  type = "kubernetes.io/dockerconfigjson"
}

resource "helm_release" "airs_gw" {
  name      = var.helm_release_name
  chart     = var.chart_path
  namespace = kubernetes_namespace.airs.metadata[0].name

  # Chart renders k8s objects directly (no external repo); wait for rollout.
  wait    = true
  timeout = 600

  values = [yamlencode({
    images = {
      gatewayImage = {
        repository = var.image_repository
        tag        = var.image_tag
      }
    }

    imagePullSecrets = [
      { name = kubernetes_secret.registry.metadata[0].name },
    ]

    # Workload Identity: bind the KSA to the Vertex-enabled GSA (stage 30-iam).
    serviceAccount = {
      create = true
      name   = var.ksa_name
      annotations = {
        "iam.gke.io/gcp-service-account" = local.gsa_email
      }
    }

    # Sensitive keys come from the existing Secret; the rest are plain values.
    # REDIS_URL / CACHE_STORE are intentionally omitted so the chart wires the
    # bundled Redis (redis://<release>-redis:6379) automatically.
    environment = {
      create         = false
      existingSecret = var.env_secret_name
      secretKeys = [
        "PORTKEY_CLIENT_AUTH",
        "ORGANISATIONS_TO_SYNC",
      ]
      data = {
        GCP_AUTH_MODE   = "workload"
        LOG_STORE       = "control_plane"
        ANALYTICS_STORE = "control_plane"
        SERVICE_NAME    = "airsgateway"
        PORT            = tostring(var.gateway_port)
        SERVER_MODE     = "all"
      }
    }

    # ClusterIP + container-native LB (NEG) so the external ALB in stage 50 can
    # target pods directly. The BackendConfig itself is created in stage 50.
    service = {
      type = "ClusterIP"
      port = var.gateway_port
      annotations = {
        "cloud.google.com/neg"            = jsonencode({ ingress = true })
        "cloud.google.com/backend-config" = jsonencode({ default = var.backend_config_name })
      }
    }

    # Bundled Redis stays on (control-plane log/analytics store, no MinIO/Milvus).
    dataservice = { enabled = false }
    minio       = { enabled = false }
    milvus      = { enabled = false }

    # Ingress is managed in stage 50-ingress, not by the chart.
    ingress = { enabled = false }
  })]

  depends_on = [
    kubernetes_secret.env,
    kubernetes_secret.registry,
  ]
}
