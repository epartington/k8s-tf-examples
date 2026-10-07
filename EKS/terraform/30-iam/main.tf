data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = "20-eks.tfstate"
    region         = var.region
    dynamodb_table = var.state_lock_table
  }
}

locals {
  oidc_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  oidc_url = data.terraform_remote_state.eks.outputs.oidc_provider_url
}

# ---------------------------------------------------------------------------
# Gateway pod identity via IRSA (IAM Roles for Service Accounts) + Bedrock.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "gateway_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.ksa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gateway" {
  name               = "${var.cluster_name}-gateway"
  assume_role_policy = data.aws_iam_policy_document.gateway_assume.json
}

# Allow the gateway to invoke Bedrock models (the roles/aiplatform.user analog).
resource "aws_iam_role_policy" "gateway_bedrock" {
  name = "bedrock-invoke"
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:ListFoundationModels",
        "bedrock:GetFoundationModel",
      ]
      Resource = var.bedrock_model_arns
    }]
  })
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller identity via IRSA (used by the Helm install in
# stage 50). This is the analog of AKS's AGIC managed identity.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["system:serviceaccount:${var.lb_controller_namespace}:${var.lb_controller_sa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${var.cluster_name}-lbc"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume.json
}

resource "aws_iam_policy" "lb_controller" {
  name   = "${var.cluster_name}-lbc"
  policy = file("${path.module}/lb-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}
