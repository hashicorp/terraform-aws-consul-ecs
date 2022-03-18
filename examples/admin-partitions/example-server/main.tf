provider "aws" {
  region = var.region
}

locals {
  suffix = var.suffix != "" ? var.suffix : random_string.suffix.result
}

resource "random_string" "suffix" {
  length  = 6
  special = false
}


// Create ACL controller
module "acl_controller" {
  source = "../../../modules/acl-controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller-${local.suffix}"
    }
  }
  launch_type                       = var.launch_type
  consul_bootstrap_token_secret_arn = var.bootstrap_token_arn
  consul_server_http_addr           = var.hcp_private_endpoint
  ecs_cluster_arn                   = var.ecs_cluster_arn
  region                            = var.region
  subnets                           = var.subnets
  name_prefix                       = local.suffix
  consul_ecs_image                  = var.consul_ecs_image
  consul_partitions_enabled         = "-partitions-enabled"
  consul_partition                  = var.partition
}

// Create services.
resource "aws_ecs_service" "example_server" {
  name            = "example_server_${local.suffix}"
  cluster         = var.ecs_cluster_arn
  task_definition = module.example_server.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.subnets
  }
  launch_type            = var.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "example_server" {
  source = "../../../modules/mesh-task"
  family = "example_server_${local.suffix}"
  container_definitions = [{
    name      = "basic"
    image     = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential = true
  }]
  retry_join = var.retry_join
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "example_server_${local.suffix}"
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

  tls                            = true
  consul_server_ca_cert_arn      = var.consul_ca_cert_arn
  gossip_key_secret_arn          = var.gossip_key_arn
  acls                           = true
  consul_client_token_secret_arn = module.acl_controller.client_token_secret_arn
  acl_secret_name_prefix         = local.suffix
  consul_ecs_image               = var.consul_ecs_image
  consul_partition               = var.partition
  consul_namespace               = var.namespace
  consul_image                   = var.consul_image

  additional_task_role_policies = [aws_iam_policy.execute-command.arn]
}

// Policy that allows execution of remote commands in ECS tasks.
resource "aws_iam_policy" "execute-command" {
  name   = "ecs-execute-command-${local.suffix}"
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
