# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module "ecs_controller" {
  source = "../../../../modules/controller"

  name_prefix         = var.name
  ecs_cluster_arn     = var.ecs_cluster_arn
  region              = var.region
  subnets             = var.private_subnets
  consul_server_hosts = var.consul_server_hosts
  consul_ca_cert_arn  = var.consul_ca_cert_arn
  launch_type         = "FARGATE"

  consul_partitions_enabled = true
  consul_partition          = var.consul_partition

  consul_bootstrap_token_secret_arn = var.consul_server_bootstrap_token_arn

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "ecs-controller"
    }
  }

  consul_ecs_image = var.consul_ecs_image
  tls              = true
}