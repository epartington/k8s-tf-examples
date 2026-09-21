# 20-gke — private cluster + node pool

Creates the private, VPC-native GKE cluster and its node pool, with Workload
Identity enabled. State prefix `20-gke`. **Slowest stage — cluster creation is
typically ~8–15 min.**

## Creates

- `google_container_cluster.gke` — private nodes, **public control-plane endpoint
  restricted to `authorized_networks`**, VPC-native (GKE-allocated pod/service
  ranges), Workload Identity pool `<project>.svc.id.goog`.
- `google_container_node_pool.primary` — `node_count` × `machine_type`, shielded
  nodes, `GKE_METADATA` (Workload Identity) enabled.

## Reads

- `10-network` — VPC + subnet to place the cluster in.

## Inputs used (from `../terraform.tfvars`)

`project_id`, `region`, `node_count`, `machine_type`, `release_channel`,
`master_ipv4_cidr`, `authorized_networks`.

> **`authorized_networks` is critical.** Stages 40/50 (and any `kubectl`/`helm`)
> reach the cluster through the *public* control-plane endpoint locked to these
> CIDRs. This machine's egress IP must be in the list, or those stages can't
> connect. If your IP changes, update the value and re-apply this stage.

## Run

```sh
cd 20-gke
terraform init -backend-config="bucket=$(terraform -chdir=../00-bootstrap output -raw state_bucket)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`cluster_name`, `location`, `endpoint` (sensitive), `ca_certificate` (sensitive),
`workload_pool`. Stages 40/50 consume `endpoint` + `ca_certificate` to configure
the kubernetes/helm providers.

## Notes

- To use `kubectl` against this cluster you need the auth plugin:
  `gcloud components install gke-gcloud-auth-plugin`, then
  `gcloud container clusters get-credentials <cluster_name> --zone <location> --project <project>`.
