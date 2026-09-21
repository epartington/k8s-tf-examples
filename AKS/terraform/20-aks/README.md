# 20-aks — AKS cluster + system node pool

Creates the AKS cluster with the OIDC issuer and Workload Identity enabled, a
public API server locked to `authorized_networks`, and egress through the
10-network NAT Gateway. State key `20-aks.tfstate`. **Slowest stage — cluster
creation is typically ~5–10 min.**

## Creates

- `azurerm_kubernetes_cluster.aks` — system node pool (`node_count` × `vm_size`)
  in the node subnet, Azure CNI **overlay**, `load_balancer_sku = standard`,
  `outbound_type = userAssignedNATGateway`, `oidc_issuer_enabled = true`,
  `workload_identity_enabled = true`, and
  `api_server_access_profile.authorized_ip_ranges = authorized_networks`.

## Reads

- `10-network` — `resource_group_name`, `location`, `aks_subnet_id`.

## Inputs used (from `../terraform.tfvars`)

`subscription_id`, `state_resource_group`, `storage_account`, `cluster_name`,
`node_count`, `vm_size`, `kubernetes_version` (optional), `authorized_networks`.

> **`authorized_networks` is critical.** Stages 40/50 (and any `kubectl`/`helm`)
> reach the cluster through the *public* API server endpoint locked to these
> CIDRs. This machine's egress IP must be in the list, or those stages can't
> connect. If your IP changes, update the value and re-apply this stage. Leaving
> it empty leaves the API server open.

## Run

```sh
cd 20-aks
terraform init \
  -backend-config="resource_group_name=$(terraform -chdir=../00-bootstrap output -raw resource_group_name)" \
  -backend-config="storage_account_name=$(terraform -chdir=../00-bootstrap output -raw storage_account_name)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`cluster_name`, `resource_group_name`, `location`, `node_resource_group`,
`oidc_issuer_url`, and the (sensitive) `host` / `client_certificate` /
`client_key` / `cluster_ca_certificate` from the cluster `kube_config`. Stage 30
consumes `oidc_issuer_url`; stages 40/50 consume the kube_config values to
configure the kubernetes/helm providers.

## Notes

- To use `kubectl` against this cluster:
  `az aks get-credentials -g <resource_group> -n <cluster_name>`, then
  `kubectl get nodes`.
- The `outbound_type = userAssignedNATGateway` binding relies on the NAT Gateway
  already being associated to the node subnet in stage 10 — apply order matters.
