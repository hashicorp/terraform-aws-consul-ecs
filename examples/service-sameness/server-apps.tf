# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

module "server_app_dc1" {
  datacenter      = local.datacenter_1
  source          = "./server-app"
  name            = var.name
  region          = var.region
  ecs_cluster_arn = module.cluster1.ecs_cluster.arn
  private_subnets = module.dc1.private_subnets
  log_group_name  = module.cluster1.log_group.name
  port            = "9090"

  consul_server_hosts = module.dc1.dev_consul_server.server_dns
  consul_ca_cert_arn  = module.dc1.dev_consul_server.ca_cert_arn
  consul_ecs_image    = var.consul_ecs_image
}

module "server_app_dc1_part1" {
  depends_on      = [module.ecs_controller_dc1_part1_partition]
  datacenter      = local.datacenter_1
  source          = "./server-app"
  name            = var.name
  region          = var.region
  ecs_cluster_arn = module.cluster2.ecs_cluster.arn
  private_subnets = module.dc1.private_subnets
  log_group_name  = module.cluster2.log_group.name
  port            = "9090"

  consul_server_hosts = module.dc1.dev_consul_server.server_dns
  consul_ca_cert_arn  = module.dc1.dev_consul_server.ca_cert_arn
  consul_ecs_image    = var.consul_ecs_image
  consul_partition    = var.dc1_consul_admin_partition
}

module "server_app_dc2" {
  source          = "./server-app"
  datacenter      = local.datacenter_2
  name            = var.name
  region          = var.region
  ecs_cluster_arn = module.cluster3.ecs_cluster.arn
  private_subnets = module.dc2.private_subnets
  log_group_name  = module.cluster3.log_group.name
  port            = "9090"

  consul_server_hosts = module.dc2.dev_consul_server.server_dns
  consul_ca_cert_arn  = module.dc2.dev_consul_server.ca_cert_arn
  consul_ecs_image    = var.consul_ecs_image
}