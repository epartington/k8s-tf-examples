variable "region" {
  type        = string
  description = "AWS region for the network."
}

variable "name_prefix" {
  type        = string
  description = "Name prefix for network resources."
  default     = "airs-gw"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name, used to tag subnets for the AWS Load Balancer Controller and cluster discovery. Must match stage 20-eks."
  default     = "airs-gw-eks"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for the public subnets (one per AZ). Host the NAT Gateway and the internet-facing ALB."
  default     = ["10.20.0.0/20", "10.20.16.0/20"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for the private subnets (one per AZ). Host the EKS nodes."
  default     = ["10.20.64.0/20", "10.20.80.0/20"]
}
