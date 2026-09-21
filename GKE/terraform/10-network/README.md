# 10-network — isolated VPC, egress, firewall, static IP

Stands up the isolated network the cluster runs in. First stage to use the **GCS
remote backend** (state prefix `10-network`).

## Creates

- `google_compute_network.vpc` + `google_compute_subnetwork.subnet` — custom-mode
  VPC and a single regional subnet (`subnet_cidr`, private Google access on).
  Pods/services secondary ranges are left to GKE to auto-allocate unless
  `pods_cidr`/`services_cidr` are set.
- `google_compute_router.router` + `google_compute_router_nat.nat` — Cloud NAT so
  private nodes have egress (image pulls, reaching the Portkey SaaS control plane).
- `google_compute_firewall.allow_internal` / `allow_master` / `allow_health_checks`
  — intra-VPC traffic, control-plane→node webhooks, and Google LB health-check ranges.
- `google_compute_global_address.gateway_ip` — the global static IP the stage-50
  HTTPS load balancer binds to.

## Reads

Nothing (does not read other stages).

## Inputs used (from `../terraform.tfvars`)

`project_id`, `region`, `subnet_cidr`, optional `pods_cidr` / `services_cidr`.

## Run

```sh
cd 10-network
terraform init -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`network_name` / `network_self_link`, `subnet_name` / `subnet_self_link`,
`pods_range_name`, `services_range_name`, `static_ip_name`, `static_ip_address`.

The `static_ip_address` is your eventual load-balancer IP — note it, since the
nip.io fallback domain derives from it (`<ip>.nip.io`).
