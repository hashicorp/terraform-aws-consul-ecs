provider "aws" {
  region = var.region
}

// Create ACL controller for cluster 1
module "acl_controller_1" {
  source = "../../../../../../modules/acl-controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller-${var.suffix_1}"
    }
  }
  launch_type                       = var.launch_type
  consul_bootstrap_token_secret_arn = var.bootstrap_token_secret_arn
  consul_server_http_addr           = var.consul_private_endpoint_url
  ecs_cluster_arn                   = var.ecs_cluster_1_arn
  region                            = var.region
  subnets                           = var.subnets
  name_prefix                       = var.suffix_1
  consul_ecs_image                  = var.consul_ecs_image
  consul_partitions_enabled         = true
  consul_partition                  = var.client_partition
}

// Create services.
resource "aws_ecs_service" "test_client" {
  name            = "test_client_${var.suffix_1}"
  cluster         = var.ecs_cluster_1_arn
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
  family = "test_client_${var.suffix_1}"
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
      destinationName      = "test_server_${var.suffix_2}"
      destinationPartition = var.server_partition
      destinationNamespace = var.server_namespace
      localBindPort        = 1234
    }
  ]
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "test_client_${var.suffix_1}"
    }
  }
  outbound_only = true

  tls                            = true
  acls                           = true
  acl_secret_name_prefix         = var.suffix_1
  gossip_key_secret_arn          = var.gossip_key_secret_arn
  consul_server_ca_cert_arn      = var.consul_ca_cert_secret_arn
  consul_client_token_secret_arn = module.acl_controller_1.client_token_secret_arn
  consul_ecs_image               = var.consul_ecs_image
  consul_image                   = var.consul_image
  consul_partition               = var.client_partition
  consul_namespace               = var.client_namespace

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
}

// Create ACL controller for cluster 2
module "acl_controller_2" {
  source = "../../../../../../modules/acl-controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller-${var.suffix_2}"
    }
  }
  launch_type                       = var.launch_type
  consul_bootstrap_token_secret_arn = var.bootstrap_token_secret_arn
  consul_server_http_addr           = var.consul_private_endpoint_url
  ecs_cluster_arn                   = var.ecs_cluster_2_arn
  region                            = var.region
  subnets                           = var.subnets
  name_prefix                       = var.suffix_2
  consul_ecs_image                  = var.consul_ecs_image
  consul_partitions_enabled         = true
  consul_partition                  = var.server_partition
}

// Create services.
resource "aws_ecs_service" "test_server" {
  name            = "test_server_${var.suffix_2}"
  cluster         = var.ecs_cluster_2_arn
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
  family = "test_server_${var.suffix_2}"
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
      awslogs-stream-prefix = "test_server_${var.suffix_2}"
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
  acls                           = true
  acl_secret_name_prefix         = var.suffix_2
  gossip_key_secret_arn          = var.gossip_key_secret_arn
  consul_server_ca_cert_arn      = var.consul_ca_cert_secret_arn
  consul_client_token_secret_arn = module.acl_controller_2.client_token_secret_arn
  consul_ecs_image               = var.consul_ecs_image
  consul_image                   = var.consul_image
  consul_partition               = var.server_partition
  consul_namespace               = var.server_namespace

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
}

resource "aws_iam_policy" "execute_command" {
  name   = "ecs-execute-command-${var.suffix_1}"
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
