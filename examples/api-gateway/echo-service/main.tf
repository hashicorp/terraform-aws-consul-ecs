# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

resource "aws_ecs_service" "echo_app" {
  name            = "echo-app-${var.name}"
  cluster         = var.ecs_cluster_arn
  task_definition = module.echo_app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.private_subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

module "echo_app" {
  source             = "../../../modules/mesh-task"
  family             = "echo-app-${var.name}"
  port               = "3000"
  log_configuration  = local.echo_app_log_config
  acls               = true
  tls                = true
  consul_ca_cert_arn = var.consul_ca_cert_arn
  container_definitions = [{
    name             = "echo-app"
    image            = "k8s.gcr.io/ingressconformance/echoserver:v0.0.1"
    essential        = true
    logConfiguration = local.echo_app_log_config
    environment = [
      {
        name  = "SERVICE_NAME"
        value = "echo-app-${var.name}"
      }
    ]
  }]
  consul_server_hosts = var.consul_server_hosts
}

locals {
  echo_app_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "echo-app"
    }
  }
}