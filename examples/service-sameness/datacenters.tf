# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

locals {
  datacenter_1 = var.datacenter_names[0]
  datacenter_2 = var.datacenter_names[1]
}

module "dc1" {
  source = "./datacenter"

  name            = "${var.name}-${local.datacenter_1}"
  ecs_cluster_arn = module.cluster1.ecs_cluster.arn
  datacenter      = local.datacenter_1
  lb_ingress_ip   = var.lb_ingress_ip
  private_subnets = module.dc1_vpc.private_subnets
  public_subnets  = module.dc1_vpc.public_subnets
  region          = var.region
  vpc             = module.dc1_vpc
  log_group_name  = module.cluster1.log_group.name

  consul_license = var.consul_license

  consul_server_startup_timeout = var.consul_server_startup_timeout
}

module "dc2" {
  source = "./datacenter"

  name            = "${var.name}-${local.datacenter_2}"
  ecs_cluster_arn = module.cluster3.ecs_cluster.arn
  datacenter      = local.datacenter_2
  lb_ingress_ip   = var.lb_ingress_ip
  private_subnets = module.dc2_vpc.private_subnets
  public_subnets  = module.dc2_vpc.public_subnets
  region          = var.region
  vpc             = module.dc2_vpc
  log_group_name  = module.cluster3.log_group.name

  consul_license = var.consul_license

  consul_server_startup_timeout = var.consul_server_startup_timeout
}

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
