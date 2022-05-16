locals {
  primary_datacenter = var.datacenter_names[0]
}

module "dc1" {
  source = "./datacenter"

  datacenter = var.datacenter_names[0]
  // Should be `[module.dc2.dev_consul_server.server_dns]`
  // But that would create a circular dependency. So predict the server name.
  #retry_join_wan     = ["${var.name}-${var.datacenter_names[1]}-consul-server.consul-${var.datacenter_names[1]}"]
  lb_ingress_ip      = var.lb_ingress_ip
  name               = "${var.name}-${var.datacenter_names[0]}"
  private_subnets    = module.dc1_vpc.private_subnets
  public_subnets     = module.dc1_vpc.public_subnets
  region             = var.region
  vpc                = module.dc1_vpc
  primary_datacenter = local.primary_datacenter

  enable_mesh_gateway_wan_federation = true
}

module "dc2" {
  source = "./datacenter"

  datacenter = var.datacenter_names[1]
  #retry_join_wan     = ["${var.name}-${var.datacenter_names[0]}-consul-server.consul-${var.datacenter_names[0]}"]
  lb_ingress_ip      = var.lb_ingress_ip
  name               = "${var.name}-${var.datacenter_names[1]}"
  private_subnets    = module.dc2_vpc.private_subnets
  public_subnets     = module.dc2_vpc.public_subnets
  region             = var.region
  vpc                = module.dc2_vpc
  primary_datacenter = local.primary_datacenter
  primary_gateways   = ["${module.dc1_gateway.lb_dns_name}:8443"]

  enable_mesh_gateway_wan_federation = true
}

# // Each Consul server has its own security group that needs to allow traffic from the other.
# resource "aws_security_group_rule" "ingress_from_dc1" {
#   description              = "Access from dc1"
#   type                     = "ingress"
#   from_port                = 0
#   to_port                  = 0
#   protocol                 = "-1"
#   source_security_group_id = module.dc1.dev_consul_server.security_group_id
#   security_group_id        = module.dc2.dev_consul_server.security_group_id
# }

# resource "aws_security_group_rule" "ingress_from_dc2" {
#   description              = "Access from dc2"
#   type                     = "ingress"
#   from_port                = 0
#   to_port                  = 0
#   protocol                 = "-1"
#   source_security_group_id = module.dc2.dev_consul_server.security_group_id
#   security_group_id        = module.dc1.dev_consul_server.security_group_id
# }


// Our app tasks need to allow ingress from the dev-server (in the relevant dc).
// The apps use the default security group so we allow ingress to default from both dev-servers.
resource "aws_security_group_rule" "default_ingress_from_dc1" {
  description              = "Access from dev-server in dc1"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.dc1.dev_consul_server.security_group_id
  security_group_id        = module.dc1_vpc.default_security_group_id
}

resource "aws_security_group_rule" "default_ingress_from_dc2" {
  description              = "Access from dev-server in dc2"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.dc2.dev_consul_server.security_group_id
  security_group_id        = module.dc2_vpc.default_security_group_id
}