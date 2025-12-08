# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

module "ecs_controller_dc1_default_partition" {
  source = "./controller"

  name            = "${var.name}-${local.datacenter_1}-default"
  region          = var.region
  ecs_cluster_arn = module.cluster1.ecs_cluster.arn
  private_subnets = module.dc1_vpc.private_subnets
  log_group_name  = module.cluster1.log_group.name

  consul_server_hosts               = module.dc1.dev_consul_server.server_dns
  consul_server_bootstrap_token_arn = module.dc1.dev_consul_server.bootstrap_token_secret_arn
  consul_ca_cert_arn                = module.dc1.dev_consul_server.ca_cert_arn
  consul_ecs_image                  = var.consul_ecs_image
}

module "ecs_controller_dc1_part1_partition" {
  source = "./controller"

  name            = "${var.name}-${local.datacenter_1}-${var.dc1_consul_admin_partition}"
  region          = var.region
  ecs_cluster_arn = module.cluster2.ecs_cluster.arn
  private_subnets = module.dc1_vpc.private_subnets
  log_group_name  = module.cluster2.log_group.name

  consul_server_hosts               = module.dc1.dev_consul_server.server_dns
  consul_server_bootstrap_token_arn = module.dc1.dev_consul_server.bootstrap_token_secret_arn
  consul_ca_cert_arn                = module.dc1.dev_consul_server.ca_cert_arn
  consul_ecs_image                  = var.consul_ecs_image
  consul_partition                  = var.dc1_consul_admin_partition
}

module "ecs_controller_dc2_default_partition" {
  source = "./controller"

  name            = "${var.name}-${local.datacenter_2}-default"
  region          = var.region
  ecs_cluster_arn = module.cluster3.ecs_cluster.arn
  private_subnets = module.dc2_vpc.private_subnets
  log_group_name  = module.cluster3.log_group.name

  consul_server_hosts               = module.dc2.dev_consul_server.server_dns
  consul_server_bootstrap_token_arn = module.dc2.dev_consul_server.bootstrap_token_secret_arn
  consul_ca_cert_arn                = module.dc2.dev_consul_server.ca_cert_arn
  consul_ecs_image                  = var.consul_ecs_image
}