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

# The client app is part of the service mesh. It tries
# to make a call to the external non mesh server app through
# a terminating gateway
resource "aws_ecs_service" "example_client_app" {
  name            = "${var.name}-example-client-app"
  cluster         = aws_ecs_cluster.cluster_one.arn
  task_definition = module.example_client_app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.vpc.private_subnets
  }
  launch_type    = "FARGATE"
  propagate_tags = "TASK_DEFINITION"
  load_balancer {
    target_group_arn = aws_lb_target_group.example_client_app.arn
    container_name   = "example-client-app"
    container_port   = 9090
  }
  enable_execute_command = true
}

module "example_client_app" {
  source = "../../modules/mesh-task"
  family = "${var.name}-example-client-app"
  port   = "9090"
  upstreams = [
    {
      destinationName = "${var.name}-external-server-app"
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
  enable_transparent_proxy      = false
}

resource "aws_lb" "example_client_app" {
  name               = "${var.name}-example-client-app"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.example_client_app_alb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_security_group" "example_client_app_alb" {
  name   = "${var.name}-example-client-app-alb"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "Access to example client application."
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["${var.lb_ingress_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "ingress_from_client_alb_to_ecs" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.example_client_app_alb.id
  security_group_id        = data.aws_security_group.vpc_default.id
}

resource "aws_security_group_rule" "ingress_from_server_alb_to_ecs" {
  type                     = "ingress"
  from_port                = 8500
  to_port                  = 8500
  protocol                 = "tcp"
  source_security_group_id = module.dc1.dev_consul_server.lb_security_group_id
  security_group_id        = data.aws_security_group.vpc_default.id
}

resource "aws_lb_target_group" "example_client_app" {
  name                 = "${var.name}-example-client-app"
  port                 = 9090
  protocol             = "HTTP"
  vpc_id               = module.vpc.vpc_id
  target_type          = "ip"
  deregistration_delay = 10
  health_check {
    path                = "/health"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    interval            = 60
  }
}

resource "aws_lb_listener" "example_client_app" {
  load_balancer_arn = aws_lb.example_client_app.arn
  port              = "9090"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example_client_app.arn
  }
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = var.name
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
}
