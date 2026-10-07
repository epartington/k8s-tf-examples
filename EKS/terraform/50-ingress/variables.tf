variable "region" {
  type        = string
  description = "AWS region."
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket holding remote state (10-network, 20-eks, 30-iam, 40-aigateway outputs)."
}

variable "state_lock_table" {
  type        = string
  description = "DynamoDB table used for state locking."
  default     = "airs-gw-tflock"
}

variable "domain" {
  type        = string
  description = "FQDN for the gateway. The ALB has a DNS name, not a static IP, so point a CNAME at the ALB (output alb_hostname), or reach the ALB directly with a Host header (curl --resolve). Leave empty to use default_domain."
  default     = ""
}

variable "default_domain" {
  type        = string
  description = "Placeholder FQDN used for host-based routing + the self-signed cert when 'domain' is empty. Reach it via the ALB DNS name with a Host header / --resolve."
  default     = "airs-gw.local"
}

variable "mcp_domain" {
  type        = string
  description = "FQDN for the MCP endpoint (SAN on the same cert, routed to the MCP port via the same ALB/WAF). Leave empty to derive 'mcp.<gateway-domain>'. Only used when the gateway runs with MCP enabled (stage 40 server_mode 'all'/'mcp')."
  default     = ""
}

variable "allowed_source_ranges" {
  type        = list(string)
  description = "Source CIDRs allowed through the WAF web ACL to reach the ALB. Everything else is blocked (403). Empty leaves the web ACL open (default allow)."
  default     = []
}

variable "health_check_path" {
  type        = string
  description = "HTTP path the ALB target-group health check hits on the gateway."
  default     = "/v1/health"
}

variable "tls_cert_arn" {
  type        = string
  description = "ARN of an existing ACM certificate to use on the ALB listener. Leave empty to generate a self-signed cert and import it to ACM (POV default)."
  default     = ""
}

variable "web_acl_name" {
  type        = string
  description = "Name of the WAFv2 web ACL associated with the ALB."
  default     = "airs-gw-waf"
}

variable "cert_name" {
  type        = string
  description = "Name tag for the imported self-signed ACM certificate."
  default     = "airs-gw-cert"
}

variable "ingress_name" {
  type        = string
  description = "Name of the Ingress object (also the ALB group name)."
  default     = "airs-gw"
}

variable "ingress_class_name" {
  type        = string
  description = "Ingress class the AWS Load Balancer Controller watches."
  default     = "alb"
}

variable "lb_controller_chart_version" {
  type        = string
  description = "Version of the aws-load-balancer-controller Helm chart. Leave empty for the latest published version."
  default     = ""
}

variable "lb_controller_chart_repository" {
  type        = string
  description = "Helm repository for the AWS Load Balancer Controller chart."
  default     = "https://aws.github.io/eks-charts"
}

variable "cluster_insecure_tls" {
  type        = bool
  description = "Skip TLS verification of the cluster API server endpoint for the kubernetes/helm providers. Set true ONLY when a TLS-inspecting proxy (corporate MITM) sits between the operator and the cluster, so the endpoint presents the proxy's cert instead of the EKS cluster CA. The bearer token still authenticates. Leave false for a normal secure connection."
  default     = false
}
