# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  server_suffix = lower(random_string.server_suffix.result)
}

resource "random_string" "server_suffix" {
  length  = 6
  special = false
}

// Create ACL controller
module "acl_controller_server" {
  source = "../../../modules/acl-controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller-${local.server_suffix}"
    }
  }
  launch_type                       = local.launch_type
  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn
  consul_server_http_addr           = hcp_consul_cluster.this.consul_private_endpoint_url
  ecs_cluster_arn                   = aws_ecs_cluster.cluster_2.arn
  region                            = var.region
  subnets                           = module.vpc.private_subnets
  name_prefix                       = local.server_suffix
  consul_ecs_image                  = var.consul_ecs_image
  consul_partitions_enabled         = true
  consul_partition                  = consul_admin_partition.part2.name
}

// Create services.
resource "aws_ecs_service" "example_server" {
  name            = "example_server_${local.server_suffix}"
  cluster         = aws_ecs_cluster.cluster_2.arn
  task_definition = module.example_server.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.vpc.private_subnets
  }
  launch_type            = local.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "example_server" {
  source = "../../../modules/mesh-task"
  family = "example_server_${local.server_suffix}"
  container_definitions = [{
    name      = "basic"
    image     = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential = true
  }]
  retry_join = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["retry_join"]
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "example_server_${local.server_suffix}"
    }
  }
  checks = [
    {
      checkId  = "server-http"
      name     = "HTTP health check on port 9090"
      http     = "http://localhost:9090/health"
      method   = "GET"
      timeout  = "10s"
      interval = "2s"
    }
  ]
  port = 9090

  tls                       = true
  acls                      = true
  consul_http_addr          = hcp_consul_cluster.this.consul_private_endpoint_url
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_server_ca_cert_arn = aws_secretsmanager_secret.consul_ca_cert.arn
  consul_ecs_image          = var.consul_ecs_image
  consul_partition          = consul_admin_partition.part2.name
  consul_namespace          = consul_namespace.ns2.name
  consul_image              = var.consul_image

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
}
