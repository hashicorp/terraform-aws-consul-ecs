# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  example_server_app_name = "example-server-app"
  example_server_app_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "server"
    }
  }
}

module "example_server_app" {
  source              = "../../../modules/mesh-task"
  family              = local.example_server_app_name
  consul_service_name = local.example_server_app_name
  port                = var.port
  acls                = true
  consul_server_hosts = var.consul_server_hosts
  tls                 = true
  consul_ca_cert_arn  = var.consul_ca_cert_arn
  log_configuration   = local.example_server_app_log_config
  container_definitions = [{
    name             = local.example_server_app_name
    image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential        = true
    logConfiguration = local.example_server_app_log_config
    environment = [
      {
        name  = "NAME"
        value = local.example_server_app_name
      }
    ]
  }]

  consul_ecs_image = var.consul_ecs_image
  consul_partition = var.consul_partition
  consul_namespace = "default"
}

resource "aws_ecs_service" "example_server_app" {
  name            = local.example_server_app_name
  cluster         = var.ecs_cluster_arn
  task_definition = module.example_server_app.task_definition_arn
  desired_count   = var.desired_tasks
  network_configuration {
    subnets = var.private_subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}
