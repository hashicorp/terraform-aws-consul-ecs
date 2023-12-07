# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "this" {}

data "aws_security_group" "vpc_default" {
  name   = "default"
  vpc_id = module.vpc.vpc_id
}

# The client app is part of the service mesh. It calls
# the server app through the service mesh.
resource "aws_ecs_service" "example_client_app" {
  name            = "${var.name}-example-client-app"
  cluster         = aws_ecs_cluster.this.arn
  task_definition = module.example_client_app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.vpc.private_subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

module "example_client_app" {
  source = "../../modules/mesh-task"
  family = "${var.name}-example-client-app"
  port   = "9090"
  upstreams = [
    {
      destinationName = "${var.name}-example-server-app"
      localBindPort   = 1234
    }
  ]
  acls               = true
  tls                = true
  consul_ca_cert_arn = module.dc1.dev_consul_server.ca_cert_arn
  log_configuration  = local.example_client_app_log_config
  container_definitions = [{
    name             = "example-client-app"
    image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential        = true
    logConfiguration = local.example_client_app_log_config
    environment = [
      {
        name  = "NAME"
        value = "${var.name}-example-client-app"
      },
      {
        name  = "UPSTREAM_URIS"
        value = "http://localhost:1234"
      }
    ]
    portMappings = [
      {
        containerPort = 9090
        hostPort      = 9090
        protocol      = "tcp"
      }
    ]
    cpu         = 0
    mountPoints = []
    volumesFrom = []
    # An ECS health check. This will be automatically synced into Consul.
    healthCheck = {
      command  = ["CMD-SHELL", "curl localhost:9090/health"]
      interval = 30
      retries  = 3
      timeout  = 5
    }
  }]
  consul_server_hosts           = module.dc1.dev_consul_server.server_dns
  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
}

resource "aws_security_group_rule" "ingress_from_server_alb_to_ecs" {
  type                     = "ingress"
  from_port                = 8500
  to_port                  = 8500
  protocol                 = "tcp"
  source_security_group_id = module.dc1.dev_consul_server.lb_security_group_id
  security_group_id        = data.aws_security_group.vpc_default.id
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = var.name
}

# The server app is part of the service mesh. It's called
# by the client app.
resource "aws_ecs_service" "example_server_app" {
  name            = "${var.name}-example-server-app"
  cluster         = aws_ecs_cluster.this.arn
  task_definition = module.example_server_app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.vpc.private_subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

module "example_server_app" {
  source             = "../../modules/mesh-task"
  family             = "${var.name}-example-server-app"
  port               = "9090"
  log_configuration  = local.example_server_app_log_config
  acls               = true
  tls                = true
  consul_ca_cert_arn = module.dc1.dev_consul_server.ca_cert_arn
  container_definitions = [{
    name             = "example-server-app"
    image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential        = true
    logConfiguration = local.example_server_app_log_config
    environment = [
      {
        name  = "NAME"
        value = "${var.name}-example-server-app"
      }
    ]
    # An ECS health check. This will be automatically synced into Consul.
    healthCheck = {
      command  = ["CMD-SHELL", "curl -f http://localhost:9090/health"]
      interval = 5
      retries  = 3
      timeout  = 10
    }
  }]
  consul_server_hosts = module.dc1.dev_consul_server.server_dns
}

resource "consul_config_entry" "example_client_app_defaults" {
  kind     = "service-defaults"
  name     = "${var.name}-example-client-app"
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Protocol = "http"
  })
}

resource "consul_config_entry" "example_server_app_defaults" {
  kind     = "service-defaults"
  name     = "${var.name}-example-server-app"
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Protocol = "http"
  })
}

// API gateway http route information for echo services
resource "consul_config_entry" "api_gw_http_route_client_app" {
  depends_on = [consul_config_entry.example_client_app_defaults, consul_config_entry.api_gateway_entry]

  name = "${var.name}-client-app-http-route"
  kind = "http-route"

  config_json = jsonencode({
    Rules = [
      {
        Matches = [
          {
            Path = {
              Match = "prefix"
              Value = "/"
            }
          }
        ]
        Services = [
          {
            Name = "${var.name}-example-client-app"
          }
        ]
      }
    ]

    Parents = [
      {
        Kind        = "api-gateway"
        Name        = "${var.name}-api-gateway"
        SectionName = "api-gw-http-listener"
      }
    ]
  })

  provider = consul.dc1-cluster
}

locals {
  example_client_app_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "client"
    }
  }

  example_server_app_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "app"
    }
  }
}
