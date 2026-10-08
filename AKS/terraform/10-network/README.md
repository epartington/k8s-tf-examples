# 10-network — VNet, subnets, NAT Gateway, NSG, App Gateway IP

Creates the isolated network for the POV: the workload resource group, a VNet
with dedicated node and Application Gateway subnets, NAT Gateway egress, an NSG,
and the static public IP for the stage-50 Application Gateway. State key
`10-network.tfstate`.

## Creates

- `azurerm_resource_group.main` — the workload RG used by stages 10–50.
- `azurerm_virtual_network.vnet` + `azurerm_subnet.aks` / `azurerm_subnet.appgw`
  — node subnet (traditional Azure CNI — pods get VNet IPs from here) and the
  dedicated App Gateway subnet.
- `azurerm_nat_gateway.nat` + `azurerm_public_ip.nat` (+ associations) — egress
  for image pulls and reaching `api.portkey.ai` / `albus.portkey.ai`.
- `azurerm_network_security_group.aks` (+ subnet association) — Azure's default
  rules already allow intra-VNet + AzureLoadBalancer inbound and deny the internet.
- `azurerm_public_ip.appgw` — Standard static public IP for the App Gateway
  frontend; its address seeds the nip.io domain.

## Reads

Nothing via remote state — first stage on the remote backend.

## Inputs used (from `../terraform.tfvars`)

`subscription_id`, `location`, `resource_group`, `vnet_cidr`, `aks_subnet_cidr`,
`appgw_subnet_cidr` (plus name overrides).

## Run

```sh
cd 10-network
terraform init \
  -backend-config="resource_group_name=$(terraform -chdir=../00-bootstrap output -raw resource_group_name)" \
  -backend-config="storage_account_name=$(terraform -chdir=../00-bootstrap output -raw storage_account_name)"
terraform plan  -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
cd ..
```

## Outputs

`resource_group_name`, `resource_group_id`, `location`, `vnet_id`, `vnet_name`,
`aks_subnet_id`, `appgw_subnet_id`, `appgw_public_ip_id`, `appgw_public_ip_address`,
`appgw_public_ip_name`. Stages 20/30/50 consume these.

## Notes

- The App Gateway subnet is intentionally left without a NAT Gateway association
  (App Gateway v2 manages its own outbound) and without restrictive NSG rules.
- The node subnet must be large enough for nodes **and pods** — traditional Azure
  CNI assigns pod IPs from this range (≈ nodes + max_pods × nodes). Overlay is
  intentionally not used: its pod IPs aren't routable from the App Gateway subnet,
  which breaks AGIC.
