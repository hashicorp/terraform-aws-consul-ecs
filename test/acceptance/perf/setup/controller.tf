# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module "ecs_controller" {
  source = "../../../../modules/controller"

  name_prefix         = var.name
  ecs_cluster_arn     = aws_ecs_cluster.this.arn
  region              = var.region
  subnets             = module.vpc.private_subnets
  consul_server_hosts = module.dev_consul_server.server_dns
  consul_ca_cert_arn  = aws_secretsmanager_secret.ca_cert.arn
  launch_type         = "FARGATE"
  datadog_api_key     = var.datadog_api_key

  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "ecs-controller"
    }
  }

  tls                       = true
  consul_partitions_enabled = true
  consul_partition          = "default"
}