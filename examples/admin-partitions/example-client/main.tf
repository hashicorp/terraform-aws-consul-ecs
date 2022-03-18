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


// Create ACL controllers - one per ECS cluster
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
resource "aws_ecs_service" "example_client" {
  name            = "example_client_${local.suffix}"
  cluster         = var.ecs_cluster_arn
  task_definition = module.example_client.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.subnets
  }
  launch_type            = var.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "example_client" {
  source = "../../../modules/mesh-task"
  family = "example_client_${local.suffix}"
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
  retry_join = var.retry_join
  upstreams = [
    {
      destinationName      = var.upstream_name
      destinationPartition = var.upstream_partition
      destinationNamespace = var.upstream_namespace
      localBindPort        = 1234
    }
  ]
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "example_client_${local.suffix}"
    }
  }
  outbound_only = true

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
