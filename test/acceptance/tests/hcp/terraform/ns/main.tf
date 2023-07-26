# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

locals {
  ecs_cluster_arn = var.ecs_cluster_arns[0]
}

// Create ACL controller
module "controller" {
  source = "../../../../../../modules/controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-ecs-controller-${var.suffix}"
    }
  }
  launch_type                       = var.launch_type
  consul_bootstrap_token_secret_arn = var.bootstrap_token_secret_arn
  consul_server_address             = var.consul_server_address
  ecs_cluster_arn                   = local.ecs_cluster_arn
  region                            = var.region
  subnets                           = var.subnets
  name_prefix                       = var.suffix
  consul_ecs_image                  = var.consul_ecs_image
  consul_partitions_enabled         = true
  consul_partition                  = "default"
  tls                               = true
  http_config = {
    port = var.http_port
  }
  grpc_config = {
    port = var.grpc_port
  }
}

// Create client.
resource "aws_ecs_service" "test_client" {
  name            = "test_client_${var.suffix}"
  cluster         = local.ecs_cluster_arn
  task_definition = module.test_client.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.subnets
  }
  launch_type            = var.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "test_client_${var.suffix}"
  container_definitions = [{
    name      = "basic"
    image     = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential = true
    environment = [
      {
        name  = "UPSTREAM_URIS"
        value = "http://localhost:1234"
      }
    ]
    linuxParameters = {
      initProcessEnabled = true
    }
  }]
  consul_server_address = var.consul_server_address
  upstreams = [
    {
      destinationName      = "test_server_${var.suffix}"
      destinationNamespace = var.server_namespace
      localBindPort        = 1234
    }
  ]
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "test_client_${var.suffix}"
    }
  }
  outbound_only = true

  tls              = true
  acls             = true
  consul_ecs_image = var.consul_ecs_image
  consul_image     = var.consul_image
  consul_namespace = var.client_namespace
  consul_partition = "default"

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]

  http_config = {
    port = var.http_port
  }
  grpc_config = {
    port = var.grpc_port
  }
}

// Create server.
resource "aws_ecs_service" "test_server" {
  name            = "test_server_${var.suffix}"
  cluster         = local.ecs_cluster_arn
  task_definition = module.test_server.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.subnets
  }
  launch_type            = var.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "test_server" {
  source = "../../../../../../modules/mesh-task"
  family = "test_server_${var.suffix}"
  container_definitions = [{
    name      = "basic"
    image     = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential = true
    healthCheck = {
      command  = ["CMD-SHELL", "curl -f http://localhost:9090/health || exit 1"]
      interval = 5
      retries  = 5
      timeout  = 10
    }
  }]
  consul_server_address = var.consul_server_address
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "test_server_${var.suffix}"
    }
  }
  port = 9090

  tls              = true
  acls             = true
  consul_ecs_image = var.consul_ecs_image
  consul_image     = var.consul_image
  consul_partition = "default"
  consul_namespace = var.server_namespace

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]

  http_config = {
    port = var.http_port
  }
  grpc_config = {
    port = var.grpc_port
  }
}

resource "aws_iam_policy" "execute_command" {
  name   = "ecs-execute-command-${var.suffix}"
  path   = "/"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF

}
