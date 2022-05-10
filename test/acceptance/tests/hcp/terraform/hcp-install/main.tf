provider "aws" {
  region = var.region
}

// Create ACL controller
module "acl_controller" {
  source = "../../../../../../modules/acl-controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller-${var.suffix}"
    }
  }
  launch_type                       = var.launch_type
  consul_bootstrap_token_secret_arn = var.bootstrap_token_secret_arn
  consul_server_http_addr           = var.consul_private_endpoint_url
  ecs_cluster_arn                   = var.ecs_cluster_arn
  region                            = var.region
  subnets                           = var.subnets
  name_prefix                       = var.suffix
  consul_ecs_image                  = var.consul_ecs_image
  consul_partitions_enabled         = true
  consul_partition                  = "default"
}

// Create client.
resource "aws_ecs_service" "test_client" {
  name            = "test_client_${var.suffix}"
  cluster         = var.ecs_cluster_arn
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
  retry_join = var.retry_join
  upstreams = [
    {
      destinationName = "test_server_${var.suffix}"
      localBindPort   = 1234
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

  tls                       = true
  acls                      = true
  gossip_key_secret_arn     = var.gossip_key_secret_arn
  consul_http_addr          = var.consul_private_endpoint_url
  consul_server_ca_cert_arn = var.consul_ca_cert_secret_arn
  consul_ecs_image          = var.consul_ecs_image
  consul_image              = var.consul_image
  consul_namespace          = "default"
  consul_partition          = "default"

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
}

// Create server.
resource "aws_ecs_service" "test_server" {
  name            = "test_server_${var.suffix}"
  cluster         = var.ecs_cluster_arn
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
  }]
  retry_join = var.retry_join
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "test_server_${var.suffix}"
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
  gossip_key_secret_arn     = var.gossip_key_secret_arn
  consul_http_addr          = var.consul_private_endpoint_url
  consul_server_ca_cert_arn = var.consul_ca_cert_secret_arn
  consul_ecs_image          = var.consul_ecs_image
  consul_image              = var.consul_image
  consul_partition          = "default"
  consul_namespace          = "default"

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
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
