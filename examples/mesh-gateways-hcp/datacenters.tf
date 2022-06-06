locals {
  primary_datacenter   = var.datacenter_names[0]
  secondary_datacenter = var.datacenter_names[1]

  primary_cidr   = "172.25.16.0/20"
  secondary_cidr = "172.26.16.0/20"
}

module "dc1" {
  source         = "./datacenter"
  name           = "${var.name}-${local.primary_datacenter}"
  datacenter     = local.primary_datacenter
  hvn_cidr_block = local.primary_cidr
  region         = var.region
  vpc            = module.dc1_vpc
}

module "dc2" {
  source = "./datacenter"

  name           = "${var.name}-${local.secondary_datacenter}"
  datacenter     = local.secondary_datacenter
  hvn_cidr_block = local.secondary_cidr
  region         = var.region
  vpc            = module.dc2_vpc

  is_secondary     = true
  hcp_primary_link = module.dc1.hcp_consul_self_link
}
