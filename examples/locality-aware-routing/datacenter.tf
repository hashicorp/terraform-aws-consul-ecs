# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  datacenter_name = "dc1"
}

module "dc1" {
  source = "./datacenter"

  name            = "${var.name}-${local.datacenter_name}"
  ecs_cluster_arn = module.cluster.ecs_cluster.arn
  datacenter      = local.datacenter_name
  lb_ingress_ip   = var.lb_ingress_ip
  private_subnets = module.vpc.private_subnets
  public_subnets  = module.vpc.public_subnets
  region          = var.region
  vpc             = module.vpc
  log_group_name  = module.cluster.log_group.name

  consul_license = var.consul_license
  consul_image   = var.consul_image

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
  security_group_id        = module.vpc.default_security_group_id
}

resource "consul_config_entry" "locality-settings" {
  depends_on = [module.dc1]

  kind     = "proxy-defaults"
  name     = "global"
  provider = consul.dc1-cluster

  config_json = jsonencode({
    PrioritizeByLocality = {
      Mode = "failover"
    }
  })
}

resource "consul_config_entry" "service-defaults" {
  depends_on = [module.dc1]

  kind     = "service-defaults"
  name     = module.server_app.name
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Protocol = "http"
  })
}

// Intention to allow traffic from the client app present
// in the peer datacenter.
resource "consul_config_entry" "service_intention" {
  depends_on = [module.dc1]

  kind     = "service-intentions"
  name     = module.server_app.name
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Sources = [
      {
        Name       = local.example_client_app_name
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      }
    ]
  })
}