variable "subscription_id" {
  type        = string
  description = "Existing Azure subscription ID."
}

variable "location" {
  type        = string
  description = "Azure region for the VNet, NAT Gateway and public IPs."
}

variable "resource_group" {
  type        = string
  description = "Name of the workload resource group to create. Holds every resource in stages 10-50."
  default     = "airs-gw-rg"
}

variable "vnet_name" {
  type        = string
  description = "Name of the isolated VNet to create."
  default     = "airs-gw-vnet"
}

variable "vnet_cidr" {
  type        = string
  description = "Address space for the VNet."
  default     = "10.10.0.0/16"
}

variable "aks_subnet_name" {
  type        = string
  description = "Name of the subnet that hosts AKS nodes."
  default     = "snet-aks"
}

variable "aks_subnet_cidr" {
  type        = string
  description = "CIDR for the AKS node subnet."
  default     = "10.10.0.0/20"
}

variable "appgw_subnet_name" {
  type        = string
  description = "Name of the dedicated subnet for Application Gateway (stage 50). App Gateway requires its own subnet."
  default     = "snet-appgw"
}

variable "appgw_subnet_cidr" {
  type        = string
  description = "CIDR for the Application Gateway subnet."
  default     = "10.10.16.0/24"
}

variable "nat_public_ip_name" {
  type        = string
  description = "Name of the Standard public IP used for NAT Gateway egress."
  default     = "airs-gw-nat-pip"
}

variable "nat_gateway_name" {
  type        = string
  description = "Name of the NAT Gateway that provides egress for the node subnet."
  default     = "airs-gw-nat"
}

variable "nsg_name" {
  type        = string
  description = "Name of the Network Security Group associated with the node subnet."
  default     = "airs-gw-aks-nsg"
}

variable "appgw_public_ip_name" {
  type        = string
  description = "Name of the Standard static public IP reserved for the Application Gateway frontend (stage 50)."
  default     = "airs-gw-appgw-pip"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all taggable resources (e.g. { CreatedBy = \"Eric Partington\" }). Set once in terraform.tfvars and passed to every stage."
  default     = {}
}
