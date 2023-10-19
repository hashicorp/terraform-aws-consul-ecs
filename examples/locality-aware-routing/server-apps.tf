# # Copyright (c) HashiCorp, Inc.
# # SPDX-License-Identifier: MPL-2.0

module "server_app" {
  datacenter      = local.datacenter_name
  source          = "./server-app"
  name            = "${var.name}-cluster1"
  region          = var.region
  ecs_cluster_arn = module.cluster.ecs_cluster.arn
  private_subnets = module.vpc.private_subnets
  log_group_name  = module.cluster.log_group.name
  port            = "9090"
  desired_tasks   = 2

  consul_server_hosts = module.dc1.dev_consul_server.server_dns
  consul_ca_cert_arn  = module.dc1.dev_consul_server.ca_cert_arn
  consul_ecs_image    = var.consul_ecs_image
}