# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

resource "aws_ecs_cluster" "this" {
  name               = var.name
  capacity_providers = ["FARGATE"]
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = var.name
}

module "ecs_controller" {
  source = "../../../modules/controller"

  name_prefix               = var.name
  ecs_cluster_arn           = aws_ecs_cluster.this.arn
  region                    = var.region
  subnets                   = var.private_subnets
  consul_server_hosts       = module.dev_consul_server.server_dns
  consul_ca_cert_arn        = var.ca_cert_arn
  launch_type               = "FARGATE"

  consul_bootstrap_token_secret_arn = var.bootstrap_token_arn

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "ecs-controller"
    }
  }

  consul_ecs_image = var.consul_ecs_image
  tls              = var.ca_cert_arn != ""
}
