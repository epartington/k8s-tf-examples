data "terraform_remote_state" "network" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group
    storage_account_name = var.storage_account
    container_name       = var.container_name
    key                  = "10-network.tfstate"
  }
}

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

data "terraform_remote_state" "portkey" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group
    storage_account_name = var.storage_account
    container_name       = var.container_name
    key                  = "40-aigateway.tfstate"
  }
}

data "azurerm_client_config" "current" {}

locals {
  rg                   = data.terraform_remote_state.network.outputs.resource_group_name
  location             = data.terraform_remote_state.network.outputs.location
  appgw_subnet_id      = data.terraform_remote_state.network.outputs.appgw_subnet_id
  appgw_public_ip_id   = data.terraform_remote_state.network.outputs.appgw_public_ip_id
  appgw_public_ip_addr = data.terraform_remote_state.network.outputs.appgw_public_ip_address

  agic_identity_client_id = data.terraform_remote_state.iam.outputs.agic_identity_client_id
  agic_namespace          = data.terraform_remote_state.iam.outputs.agic_namespace

  namespace    = data.terraform_remote_state.portkey.outputs.namespace
  service_name = data.terraform_remote_state.portkey.outputs.service_name
  service_port = data.terraform_remote_state.portkey.outputs.service_port
  mcp_enabled  = data.terraform_remote_state.portkey.outputs.mcp_enabled
  mcp_port     = data.terraform_remote_state.portkey.outputs.mcp_service_port

  # TLS cert needs a real FQDN. Fall back to nip.io pointing at the App Gateway IP.
  domain = var.domain != "" ? var.domain : "${local.appgw_public_ip_addr}.nip.io"

  # MCP gets its own hostname on the SAME cert/IP/WAF. With the nip.io fallback,
  # "mcp.<ip>.nip.io" resolves to the same App Gateway IP automatically.
  mcp_domain = var.mcp_domain != "" ? var.mcp_domain : "mcp.${local.domain}"

  # SANs on the self-signed cert: add the MCP host only when MCP is enabled.
  cert_dns_names = local.mcp_enabled ? [local.domain, local.mcp_domain] : [local.domain]

  # Use the supplied cert secret, or the self-signed one generated below.
  cert_secret_id = var.tls_cert_keyvault_secret_id != "" ? var.tls_cert_keyvault_secret_id : azurerm_key_vault_certificate.self_signed[0].secret_id
}

# WAF policy: allow only the POV source ranges, block everything else. A single
# Block rule negated over the allowlist implements the allowlist; when no ranges
# are supplied the policy stays open (no custom rule).
resource "azurerm_web_application_firewall_policy" "waf" {
  name                = var.waf_policy_name
  location            = local.location
  resource_group_name = local.rg

  policy_settings {
    enabled = true
    mode    = "Prevention"
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  dynamic "custom_rules" {
    for_each = length(var.allowed_source_ranges) > 0 ? [1] : []
    content {
      name      = "AllowListOnly"
      priority  = 100
      rule_type = "MatchRule"
      action    = "Block"

      match_conditions {
        match_variables {
          variable_name = "RemoteAddr"
        }
        operator           = "IPMatch"
        negation_condition = true
        match_values       = var.allowed_source_ranges
      }
    }
  }
}

# --- TLS cert in Key Vault (self-signed by default) ---

resource "azurerm_user_assigned_identity" "appgw" {
  name                = var.appgw_identity_name
  location            = local.location
  resource_group_name = local.rg
}

resource "azurerm_key_vault" "kv" {
  name                       = var.key_vault_name
  location                   = local.location
  resource_group_name        = local.rg
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
}

# The operator (Terraform principal) needs cert/secret permissions to generate
# the self-signed cert.
resource "azurerm_key_vault_access_policy" "operator" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  certificate_permissions = ["Create", "Delete", "Get", "Import", "List", "Purge", "Update"]
  secret_permissions      = ["Get", "List"]
  key_permissions         = ["Create", "Get", "List"]
}

# The App Gateway identity reads the cert (delivered as a KV secret).
resource "azurerm_key_vault_access_policy" "appgw" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.appgw.principal_id

  certificate_permissions = ["Get"]
  secret_permissions      = ["Get"]
}

resource "azurerm_key_vault_certificate" "self_signed" {
  count = var.tls_cert_keyvault_secret_id == "" ? 1 : 0

  name         = var.cert_name
  key_vault_id = azurerm_key_vault.kv.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_type   = "RSA"
      key_size   = 2048
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=${local.domain}"
      validity_in_months = 12

      # digitalSignature + keyEncipherment for a TLS server cert.
      key_usage = ["digitalSignature", "keyEncipherment"]

      # serverAuth EKU.
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      subject_alternative_names {
        dns_names = local.cert_dns_names
      }
    }
  }

  depends_on = [azurerm_key_vault_access_policy.operator]
}

# --- Application Gateway (WAF_v2) ---
#
# Created with a placeholder listener/backend/rule; AGIC (installed below) takes
# over and manages those collections from the Kubernetes Ingress. Terraform keeps
# ownership of the SKU, WAF policy association, KV-backed TLS cert, and frontend.
resource "azurerm_application_gateway" "appgw" {
  name                = var.appgw_name
  location            = local.location
  resource_group_name = local.rg

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = var.appgw_capacity
  }

  firewall_policy_id                = azurerm_web_application_firewall_policy.waf.id
  force_firewall_policy_association = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw.id]
  }

  gateway_ip_configuration {
    name      = "appgw-ipcfg"
    subnet_id = local.appgw_subnet_id
  }

  frontend_ip_configuration {
    name                 = "appgw-feip"
    public_ip_address_id = local.appgw_public_ip_id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  # KV-backed TLS cert referenced by AGIC via the Ingress annotation
  # "appgw.ingress.kubernetes.io/appgw-ssl-certificate".
  ssl_certificate {
    name                = var.cert_name
    key_vault_secret_id = local.cert_secret_id
  }

  # Placeholder config (AGIC replaces these from the Ingress).
  backend_address_pool {
    name = "placeholder-pool"
  }

  backend_http_settings {
    name                  = "placeholder-http"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  http_listener {
    name                           = "placeholder-listener"
    frontend_ip_configuration_name = "appgw-feip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "placeholder-rule"
    rule_type                  = "Basic"
    priority                   = 1
    http_listener_name         = "placeholder-listener"
    backend_address_pool_name  = "placeholder-pool"
    backend_http_settings_name = "placeholder-http"
  }

  # AGIC owns these collections at runtime; ignore drift so Terraform and AGIC
  # don't fight over the App Gateway config.
  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      http_listener,
      request_routing_rule,
      probe,
      url_path_map,
      redirect_configuration,
      frontend_port,
      tags,
    ]
  }

  depends_on = [azurerm_key_vault_access_policy.appgw]
}

# --- AGIC (Application Gateway Ingress Controller) via Helm ---
resource "helm_release" "agic" {
  name       = "ingress-azure"
  namespace  = local.agic_namespace
  repository = var.agic_chart_repository
  chart      = "ingress-azure"
  version    = var.agic_chart_version != "" ? var.agic_chart_version : null

  set {
    name  = "appgw.applicationGatewayID"
    value = azurerm_application_gateway.appgw.id
  }

  set {
    name  = "appgw.subscriptionId"
    value = var.subscription_id
  }

  # Authenticate to ARM with the AGIC managed identity via Workload Identity.
  set {
    name  = "armAuth.type"
    value = "workloadIdentity"
  }

  set {
    name  = "armAuth.identityClientID"
    value = local.agic_identity_client_id
  }

  set {
    name  = "rbac.enabled"
    value = "true"
  }

  set {
    name  = "verbosityLevel"
    value = "3"
  }

  depends_on = [azurerm_application_gateway.appgw]
}

# --- Ingress fronting the gateway (and MCP) through the App Gateway ---
resource "kubernetes_ingress_v1" "gateway" {
  metadata {
    name      = var.ingress_name
    namespace = local.namespace
    annotations = {
      "appgw.ingress.kubernetes.io/ssl-redirect"          = "true"
      "appgw.ingress.kubernetes.io/health-probe-path"     = var.health_check_path
      "appgw.ingress.kubernetes.io/appgw-ssl-certificate" = var.cert_name
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

    # MCP on its own hostname, same Service/pod (mcp_port), same App Gateway,
    # same WAF policy + cert. Only added when stage 40 enabled MCP.
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

  depends_on = [helm_release.agic]
}
