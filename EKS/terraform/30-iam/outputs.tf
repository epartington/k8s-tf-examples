output "gateway_role_arn" {
  description = "ARN of the gateway IRSA role (used for the KSA annotation in stage 40)."
  value       = aws_iam_role.gateway.arn
}

output "namespace" {
  description = "Namespace the gateway IRSA role targets."
  value       = var.namespace
}

output "ksa_name" {
  description = "KSA name the gateway IRSA role targets."
  value       = var.ksa_name
}

output "lb_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IRSA role (used by the Helm install in stage 50)."
  value       = aws_iam_role.lb_controller.arn
}

output "lb_controller_namespace" {
  description = "Namespace the AWS Load Balancer Controller runs in."
  value       = var.lb_controller_namespace
}

output "lb_controller_sa_name" {
  description = "Service account name for the AWS Load Balancer Controller."
  value       = var.lb_controller_sa_name
}
