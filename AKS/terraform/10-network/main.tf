# Workload resource group used by stages 10-50.
resource "azurerm_resource_group" "main" {
  name     = var.resource_group
  location = var.location
}

# Isolated VNet dedicated to this POV.
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_cidr]
}

# Subnet for AKS nodes (pods use Azure CNI overlay, so they don't consume this range).
resource "azurerm_subnet" "aks" {
  name                 = var.aks_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.aks_subnet_cidr]
}

# Dedicated subnet for Application Gateway v2 (stage 50). Must not carry an NSG
# that blocks the App Gateway management ports, nor a NAT Gateway association.
resource "azurerm_subnet" "appgw" {
  name                 = var.appgw_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.appgw_subnet_cidr]
}

# Egress for the private nodes: image pulls + reaching api.portkey.ai / albus.portkey.ai.
resource "azurerm_public_ip" "nat" {
  name                = var.nat_public_ip_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "nat" {
  name                = var.nat_gateway_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

# NSG on the node subnet. Azure's default rules already allow intra-VNet and
# AzureLoadBalancer inbound and deny the internet, mirroring the GKE firewall;
# add explicit rules here only if the POV needs to open extra ports.
resource "azurerm_network_security_group" "aks" {
  name                = var.nsg_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Standard static public IP for the Application Gateway frontend (stage 50).
# Its address seeds the nip.io domain, mirroring the GKE global static IP.
resource "azurerm_public_ip" "appgw" {
  name                = var.appgw_public_ip_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}
