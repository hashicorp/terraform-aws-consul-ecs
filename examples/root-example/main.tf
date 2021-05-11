provider "aws" {
  region = var.region
}

locals {
  mesh_app_log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "app"
    }
  }

  mesh_client_log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "client"
    }
  }
}

module "consul_server" {
  source                 = "./modules/server"
  tags                   = var.tags
  ecs_cluster_arn        = var.ecs_cluster
  subnets                = var.subnets
  vpc_id                 = var.vpc_id
  load_balancer_enabled  = true
  lb_subnets             = var.lb_subnets
  lb_ingress_description = var.lb_ingress_security_group_rule_description
  lb_ingress_cidr_blocks = var.lb_ingress_security_group_rule_cidr_blocks
  consul_image           = var.consul_image
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-server"
    }
  }
}

resource "aws_ecs_service" "mesh-app" {
  name            = "mesh-app"
  cluster         = var.ecs_cluster
  task_definition = module.mesh-app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
  depends_on = [
    aws_iam_role.mesh_app_task
  ]
}

module "mesh-app" {
  source             = "./modules/mesh-task"
  family             = "mesh-app"
  execution_role_arn = aws_iam_role.mesh-app-execution.arn
  task_role_arn      = aws_iam_role.mesh_app_task.arn
  port               = "9090"
  consul_image       = var.consul_image
  consul_ecs_image   = var.consul_ecs_image
  log_configuration  = local.mesh_app_log_configuration
  app_container = {
    name             = "mesh-app"
    image            = "ghcr.io/lkysow/fake-service:v0.21.0"
    essential        = true
    logConfiguration = local.mesh_app_log_configuration
    environment = [
      {
        name  = "NAME"
        value = "mesh-app"
      }
    ]
  }
  consul_server_service_name = module.consul_server.service_name
  envoy_image                = var.envoy_image
  dev_server_enabled         = var.dev_server_enabled
}

module "mesh-client" {
  source             = "./modules/mesh-task"
  family             = "mesh-client"
  execution_role_arn = aws_iam_role.mesh-app-execution.arn
  task_role_arn      = aws_iam_role.mesh_app_task.arn
  consul_image       = var.consul_image
  consul_ecs_image   = var.consul_ecs_image
  port               = "9090"
  upstreams = [
    {
      destination_name = "mesh-app"
      local_bind_port  = 1234
    }
  ]
  log_configuration = local.mesh_client_log_configuration
  app_container = {
    name             = "mesh-client"
    image            = "ghcr.io/lkysow/fake-service:v0.21.0"
    essential        = true
    logConfiguration = local.mesh_client_log_configuration
    environment = [
      {
        name  = "NAME"
        value = "mesh-client"
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
  }
  consul_server_service_name = module.consul_server.service_name
  envoy_image                = var.envoy_image
  dev_server_enabled         = var.dev_server_enabled
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = var.log_group_name
}


resource "aws_ecs_service" "mesh-client" {
  name            = "mesh-client"
  cluster         = var.ecs_cluster
  task_definition = module.mesh-client.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.subnets
  }
  launch_type    = "FARGATE"
  propagate_tags = "TASK_DEFINITION"
  load_balancer {
    target_group_arn = aws_lb_target_group.mesh-client.arn
    container_name   = "mesh-client"
    container_port   = 9090
  }
  enable_execute_command = true
  depends_on = [
    aws_iam_role.mesh_app_task
  ]
}

resource "aws_iam_role" "mesh_app_task" {
  name = "mesh-app"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
  # for discover-servers
  # todo: scope this down so it's only list and describe tasks.
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonECS_FullAccess"]

  inline_policy {
    name = "exec"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
          ]
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_lb" "mesh-client" {
  name               = var.mesh_client_app_lb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.mesh-client-alb.id]
  subnets            = var.lb_subnets
}

resource "aws_security_group" "mesh-client-alb" {
  name   = "mesh-client-alb"
  vpc_id = var.vpc_id

  ingress {
    description = var.lb_ingress_security_group_rule_description
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.lb_ingress_security_group_rule_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "mesh-client" {
  name                 = "mesh-client-alb"
  port                 = 9090
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 10
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    interval            = 60
  }
}

resource "aws_lb_listener" "mesh-client" {
  load_balancer_arn = aws_lb.mesh-client.arn
  port              = "9090"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mesh-client.arn
  }
}

resource "aws_iam_policy" "mesh-app-execution" {
  name        = "mesh-app"
  path        = "/ecs/"
  description = "mesh-app execution"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "mesh-app-execution" {
  name = "mesh-app-execution"
  path = "/ecs/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "mesh-app-execution" {
  role       = aws_iam_role.mesh-app-execution.id
  policy_arn = aws_iam_policy.mesh-app-execution.arn
}
