# 20-eks — EKS cluster + managed node group + OIDC (IRSA)

Creates the EKS cluster with a public API endpoint locked to `authorized_networks`,
a managed node group in the private subnets, and the IAM OIDC provider that IRSA
roles federate to. State key `20-eks.tfstate`. **Slowest stage — cluster creation
is typically ~10–15 min.**

## Creates

- `aws_iam_role.cluster` (+ `AmazonEKSClusterPolicy`) — the cluster role.
- `aws_iam_role.node` (+ `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`,
  `AmazonEC2ContainerRegistryReadOnly`) — a **dedicated least-privilege node role**
  (the EKS parallel of GKE's dedicated node SA), created before the node group.
- `aws_eks_cluster.this` — private nodes, public endpoint restricted to
  `authorized_networks`, placed across the 10-network subnets.
- `aws_iam_openid_connect_provider.oidc` — IRSA trust anchor (stage 30 roles).
- `aws_eks_node_group.primary` — `node_count` × `instance_type` in the private
  subnets, running as the node role.

## Reads

- `10-network` — `vpc_id`, `private_subnet_ids`, `public_subnet_ids`.

## Inputs used (from `../terraform.tfvars`)

`region`, `state_bucket`, `cluster_name`, `kubernetes_version` (optional),
`node_count`, `instance_type`, `node_disk_size_gb`, `authorized_networks`.

> **`authorized_networks` is critical.** Stages 40/50 (and any `kubectl`/`helm`)
> reach the cluster through the *public* API server endpoint locked to these CIDRs.
> This machine's egress IP must be in the list, or those stages can't connect.
> Empty opens it to `0.0.0.0/0`.

## Run

```sh
cd 20-eks
terraform init \
  -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)" \
  -backend-config="dynamodb_table=$(terraform -chdir=../00-bootstrap output -raw state_lock_table)" \
  -backend-config="region=$(terraform -chdir=../00-bootstrap output -raw region)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`cluster_name`, `cluster_endpoint`, `cluster_ca_certificate`, `oidc_provider_arn`,
`oidc_provider_url`, `node_role_arn`, `region`. Stage 30 consumes the OIDC outputs;
stages 40/50 consume the endpoint/CA for the kubernetes/helm providers.

## Notes

- To use `kubectl`: `aws eks update-kubeconfig --name <cluster_name> --region <region>`,
  then `kubectl get nodes`.
- `instance_type` defaults to `m5.xlarge` (4 vCPU / 16 GB) to match the GKE/AKS node
  spec.
- The node role is already minimal by EKS default (no AKS-style over-privilege); it
  is created explicitly here for clarity and least privilege.
