# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

module "ecs_controller_cluster1" {
  source = "./controller"

  name            = "${var.name}-cluster1"
  region          = var.region
  ecs_cluster_arn = module.cluster.ecs_cluster.arn
  private_subnets = module.vpc.private_subnets
  log_group_name  = module.cluster.log_group.name

  consul_server_hosts               = module.dc1.dev_consul_server.server_dns
  consul_server_bootstrap_token_arn = module.dc1.dev_consul_server.bootstrap_token_secret_arn
  consul_ca_cert_arn                = module.dc1.dev_consul_server.ca_cert_arn
  consul_ecs_image                  = var.consul_ecs_image
}