# 10-network — VPC, subnets, NAT Gateway, routing

Creates the isolated network for the POV: a VPC with public and private subnets
across two AZs, an internet gateway, a NAT Gateway for private egress, and the
subnet tags EKS / the AWS Load Balancer Controller need. State key
`10-network.tfstate`.

## Creates

- `aws_vpc.main` — the workload VPC (DNS support + hostnames on).
- `aws_subnet.public[*]` / `aws_subnet.private[*]` — one per AZ. Public host the
  internet-facing ALB + NAT Gateway (`kubernetes.io/role/elb`); private host the
  EKS nodes (`kubernetes.io/role/internal-elb`). Both carry the cluster shared tag.
- `aws_internet_gateway.main`, `aws_eip.nat` + `aws_nat_gateway.main` — egress for
  image pulls and reaching `api.portkey.ai` / `albus.portkey.ai`.
- Route tables + associations (public → IGW, private → NAT).

## Reads

Nothing via remote state — first stage on the `s3` backend.

## Inputs used (from `../terraform.tfvars`)

`region`, `cluster_name` (for subnet tags — must match stage 20), `vpc_cidr`,
`public_subnet_cidrs`, `private_subnet_cidrs`, `name_prefix`.

## Run

```sh
cd 10-network
terraform init \
  -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)" \
  -backend-config="dynamodb_table=$(terraform -chdir=../00-bootstrap output -raw state_lock_table)" \
  -backend-config="region=$(terraform -chdir=../00-bootstrap output -raw region)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `region`. Stages 20/50 consume
these.

## Notes

- **Multi-AZ is required** — EKS needs subnets in at least two AZs. The two CIDR
  lists must be the same length; AZs are chosen from the region automatically.
- The subnet `kubernetes.io/role/*` tags are what let the ALB controller discover
  where to place internet-facing vs internal load balancers — don't drop them.
- One NAT Gateway (single-AZ egress) keeps POV cost down; add one per AZ for HA.
