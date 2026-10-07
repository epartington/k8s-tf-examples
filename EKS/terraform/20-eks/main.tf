data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = "10-network.tfstate"
    region         = var.region
    dynamodb_table = var.state_lock_table
  }
}

locals {
  net                 = data.terraform_remote_state.network.outputs
  public_access_cidrs = length(var.authorized_networks) > 0 ? var.authorized_networks : ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# IAM: dedicated cluster role and least-privilege node role.
# (The node role is the EKS parallel of GKE's dedicated node service account.)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# EKS cluster: private nodes, public endpoint locked to authorized_networks.
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version != "" ? var.kubernetes_version : null

  vpc_config {
    subnet_ids              = concat(local.net.private_subnet_ids, local.net.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = local.public_access_cidrs
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# OIDC provider for IRSA (IAM Roles for Service Accounts). Stage 30 federates
# the gateway and LB-controller roles to this provider.
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

# Managed node group in the private subnets, running as the dedicated node role.
resource "aws_eks_node_group" "primary" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = local.net.private_subnet_ids

  instance_types = [var.instance_type]
  disk_size      = var.node_disk_size_gb

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}
