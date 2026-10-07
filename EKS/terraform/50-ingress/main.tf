data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = "10-network.tfstate"
    region         = var.region
    dynamodb_table = var.state_lock_table
  }
}

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

data "terraform_remote_state" "gateway" {
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = "40-aigateway.tfstate"
    region         = var.region
    dynamodb_table = var.state_lock_table
  }
}

locals {
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  cluster_nm = data.terraform_remote_state.eks.outputs.cluster_name
  lbc_role   = data.terraform_remote_state.iam.outputs.lb_controller_role_arn
  lbc_ns     = data.terraform_remote_state.iam.outputs.lb_controller_namespace
  lbc_sa     = data.terraform_remote_state.iam.outputs.lb_controller_sa_name

  namespace    = data.terraform_remote_state.gateway.outputs.namespace
  service_name = data.terraform_remote_state.gateway.outputs.service_name
  service_port = data.terraform_remote_state.gateway.outputs.service_port
  mcp_enabled  = data.terraform_remote_state.gateway.outputs.mcp_enabled
  mcp_port     = data.terraform_remote_state.gateway.outputs.mcp_service_port

  # The ALB has a DNS name, not a static IP (no nip.io). Host-based routing keys on
  # the domain; reach it by CNAME-ing the domain to the ALB, or with a Host header.
  domain     = var.domain != "" ? var.domain : var.default_domain
  mcp_domain = var.mcp_domain != "" ? var.mcp_domain : "mcp.${local.domain}"

  cert_dns_names = local.mcp_enabled ? [local.domain, local.mcp_domain] : [local.domain]
  cert_arn       = var.tls_cert_arn != "" ? var.tls_cert_arn : aws_acm_certificate.self_signed[0].arn

  use_allowlist = length(var.allowed_source_ranges) > 0
}

# ---------------------------------------------------------------------------
# WAFv2 web ACL (REGIONAL, for the ALB): allow only the POV source ranges.
# ---------------------------------------------------------------------------
resource "aws_wafv2_ip_set" "allow" {
  count              = local.use_allowlist ? 1 : 0
  name               = "${var.web_acl_name}-allow"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.allowed_source_ranges
}

resource "aws_wafv2_web_acl" "this" {
  name  = var.web_acl_name
  scope = "REGIONAL"

  # Default block when an allowlist is set (only listed IPs get through); default
  # allow (open) when no allowlist is supplied.
  default_action {
    dynamic "allow" {
      for_each = local.use_allowlist ? [] : [1]
      content {}
    }
    dynamic "block" {
      for_each = local.use_allowlist ? [1] : []
      content {}
    }
  }

  dynamic "rule" {
    for_each = local.use_allowlist ? [1] : []
    content {
      name     = "allow-source-ranges"
      priority = 0
      action {
        allow {}
      }
      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.allow[0].arn
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "allow-source-ranges"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.web_acl_name
    sampled_requests_enabled   = true
  }
}

# ---------------------------------------------------------------------------
# TLS cert on ACM: self-signed import by default, or bring your own (tls_cert_arn).
# ---------------------------------------------------------------------------
resource "tls_private_key" "self_signed" {
  count     = var.tls_cert_arn == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count           = var.tls_cert_arn == "" ? 1 : 0
  private_key_pem = tls_private_key.self_signed[0].private_key_pem

  subject {
    common_name = local.domain
  }

  dns_names             = local.cert_dns_names
  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "self_signed" {
  count            = var.tls_cert_arn == "" ? 1 : 0
  private_key      = tls_private_key.self_signed[0].private_key_pem
  certificate_body = tls_self_signed_cert.self_signed[0].cert_pem
  tags             = { Name = var.cert_name }
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller via Helm (authenticated via the stage-30 IRSA role).
# ---------------------------------------------------------------------------
resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = local.lbc_ns
  repository = var.lb_controller_chart_repository
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version != "" ? var.lb_controller_chart_version : null

  set {
    name  = "clusterName"
    value = local.cluster_nm
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = local.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = local.lbc_sa
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = local.lbc_role
  }
}

# ---------------------------------------------------------------------------
# Ingress fronting the gateway (and MCP) through an internet-facing ALB with the
# ACM cert and the WAF web ACL. The controller provisions the ALB from this spec.
# ---------------------------------------------------------------------------
resource "kubernetes_ingress_v1" "gateway" {
  metadata {
    name      = var.ingress_name
    namespace = local.namespace
    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
      "alb.ingress.kubernetes.io/certificate-arn"  = local.cert_arn
      "alb.ingress.kubernetes.io/wafv2-acl-arn"    = aws_wafv2_web_acl.this.arn
      "alb.ingress.kubernetes.io/healthcheck-path" = var.health_check_path
      "alb.ingress.kubernetes.io/group.name"       = var.ingress_name
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    # Gateway on the primary domain.
    rule {
      host = local.domain
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = local.service_name
              port {
                number = local.service_port
              }
            }
          }
        }
      }
    }

    # MCP on its own hostname, same Service/pod (mcp_port), same ALB, same WAF +
    # cert. Only added when stage 40 enabled MCP.
    dynamic "rule" {
      for_each = local.mcp_enabled ? [1] : []
      content {
        host = local.mcp_domain
        http {
          path {
            path      = "/"
            path_type = "Prefix"
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

  wait_for_load_balancer = true

  depends_on = [helm_release.lb_controller]
}
