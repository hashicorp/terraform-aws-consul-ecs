# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

locals {
  example_client_app_name = "example-client-app"
  example_client_app_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = module.cluster.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "client"
    }
  }
}


module "example_client_app" {
  source                   = "../../modules/mesh-task"
  family                   = local.example_client_app_name
  port                     = "9090"
  acls                     = true
  enable_transparent_proxy = false
  consul_server_hosts      = module.dc1.dev_consul_server.server_dns
  tls                      = true
  consul_ca_cert_arn       = module.dc1.dev_consul_server.ca_cert_arn
  upstreams = [
    {
      destinationName = "example-server-app"
      localBindPort   = 1234
    }
  ]
  log_configuration = local.example_client_app_log_config
  container_definitions = [
    {
      name             = "example-client-app"
      image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
      essential        = true
      logConfiguration = local.example_client_app_log_config
      environment = [
        {
          name  = "NAME"
          value = local.example_client_app_name
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
  }]

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]

  consul_ecs_image = var.consul_ecs_image
}

resource "aws_ecs_service" "example_client_app" {
  name            = local.example_client_app_name
  cluster         = module.cluster.ecs_cluster.arn
  task_definition = module.example_client_app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.dc1.private_subnets
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

resource "aws_lb" "example_client_app" {
  name               = local.example_client_app_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.example_client_app_alb.id]
  subnets            = module.dc1.public_subnets
}

resource "aws_security_group" "example_client_app_alb" {
  name   = "${local.example_client_app_name}-alb"
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
  security_group_id        = module.vpc.default_security_group_id
}

resource "aws_security_group_rule" "ingress_from_server_alb_to_ecs" {
  type                     = "ingress"
  from_port                = 8500
  to_port                  = 8500
  protocol                 = "tcp"
  source_security_group_id = module.dc1.dev_consul_server.lb_security_group_id
  security_group_id        = module.vpc.default_security_group_id
}

resource "aws_lb_target_group" "example_client_app" {
  name                 = local.example_client_app_name
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

resource "aws_lb_listener" "example_client_app" {
  load_balancer_arn = aws_lb.example_client_app.arn
  port              = "9090"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example_client_app.arn
  }
}

// Policy that allows execution of remote commands in ECS tasks.
resource "aws_iam_policy" "execute_command" {
  name   = "${var.name}-ecs-execute-command"
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