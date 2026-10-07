output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (internet-facing ALB)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (EKS nodes)."
  value       = aws_subnet.private[*].id
}

output "region" {
  description = "AWS region of the network."
  value       = var.region
}
