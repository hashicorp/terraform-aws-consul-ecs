# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module "ecs_controller" {
  depends_on = [module.dc1]
  source     = "../../modules/controller"

  name_prefix         = var.name
  ecs_cluster_arn     = aws_ecs_cluster.this.arn
  region              = var.region
  subnets             = module.vpc.private_subnets
  consul_server_hosts = module.dc1.dev_consul_server.server_dns
  consul_ca_cert_arn  = module.dc1.dev_consul_server.ca_cert_arn
  launch_type         = "FARGATE"
  consul_ecs_image    = "ganeshrockz/api-gateway"

  consul_bootstrap_token_secret_arn = module.dc1.dev_consul_server.bootstrap_token_secret_arn

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "ecs-controller"
    }
  }

  tls = true
}