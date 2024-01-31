# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  example_server_app_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "app"
    }
  }
}

# The server app is an external app that is not part of the mesh
resource "aws_ecs_service" "example_server_app" {
  name            = "${var.name}-external-server-app"
  cluster         = aws_ecs_cluster.cluster_two.arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  network_configuration {
    subnets = module.vpc.private_subnets
  }
  launch_type    = "FARGATE"
  propagate_tags = "TASK_DEFINITION"
  load_balancer {
    target_group_arn = aws_lb_target_group.example_server_app.arn
    container_name   = "example-server-app"
    container_port   = 9090
  }

  enable_execute_command = true
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name}-external-server-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  task_role_arn            = aws_iam_role.task.arn
  cpu                      = 256
  memory                   = 512

  tags = {
    "consul.hashicorp.com/mesh" = "false"
  }

  container_definitions = jsonencode([{
    name      = "example-server-app"
    image     = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential = true
    environment = [
      {
        name  = "NAME"
        value = "${var.name}-external-server-app"
      }
    ]
    portMappings = [
      {
        containerPort = 9090
        hostPort      = 9090
        protocol      = "tcp"
      }
    ]
    healthCheck = {
      command  = ["CMD-SHELL", "curl -f http://localhost:9090/health"]
      interval = 5
      retries  = 3
      timeout  = 10
    }
  }])
}

resource "aws_lb" "example_server_app" {
  name               = "${var.name}-external-server-app"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.example_server_app_alb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_security_group" "example_server_app_alb" {
  name   = "${var.name}-external-server-app-alb"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "Access to example server application."
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "ingress_from_server_service_alb_to_ecs" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.example_server_app_alb.id
  security_group_id        = data.aws_security_group.vpc_default.id
}

resource "aws_lb_target_group" "example_server_app" {
  name                 = "${var.name}-external-server-app"
  port                 = 9090
  protocol             = "HTTP"
  vpc_id               = module.vpc.vpc_id
  target_type          = "ip"
  deregistration_delay = 10
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    interval            = 60
  }
}

resource "aws_lb_listener" "example_server_app" {
  load_balancer_arn = aws_lb.example_server_app.arn
  port              = "9090"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example_server_app.arn
  }
}

resource "aws_iam_role" "task" {
  name = "${var.name}-external-server-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}