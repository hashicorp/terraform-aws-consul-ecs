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
  execution_role_arn       = aws_iam_role.this_execution.arn
  task_role_arn            = aws_iam_role.this_task.arn
  cpu                      = 256
  memory                   = 512

  tags = {
    "consul.hashicorp.com/mesh" = "false"
  }

  dynamic "volume" {
    for_each = var.volumes
    content {
      name      = volume.value["name"]
      dynamic "efs_volume_configuration" {
        for_each = contains(keys(volume.value), "efs_volume_configuration") ? [
          volume.value["efs_volume_configuration"]
        ] : []
        content {
          file_system_id          = efs_volume_configuration.value["file_system_id"]
          root_directory          = lookup(efs_volume_configuration.value, "root_directory", null)
          transit_encryption      = lookup(efs_volume_configuration.value, "transit_encryption", null)
          transit_encryption_port = lookup(efs_volume_configuration.value, "transit_encryption_port", null)
          dynamic "authorization_config" {
            for_each = contains(keys(efs_volume_configuration.value), "authorization_config") ? [
              efs_volume_configuration.value["authorization_config"]
            ] : []
            content {
              access_point_id = lookup(authorization_config.value, "access_point_id", null)
              iam             = lookup(authorization_config.value, "iam", null)
            }
          }
        }
      }
    }
  }

  container_definitions = jsonencode([{
    name      = "example-server-app"
    image     = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential = true
    logConfiguration = local.example_server_app_log_config
    command = [
      "mkdir -p /efs-certs"
#      "yum install sudo -y"
    ],
    mountPoints = [
      {
        sourceVolume  = "certs-efs"
        containerPath = "/efs-certs"
        readOnly      = true
      }
    ]
    environment = [
      {
        name  = "NAME"
        value = "${var.name}-external-server-app"
      },
      {
        name  = "TLS_CERT_LOCATION"
        value = var.cert_paths.cert_path
      },
      {
        name  = "TLS_KEY_LOCATION"
        value = var.cert_paths.key_path
      }
    ]
    portMappings = [
      {
        containerPort = 9090
        hostPort      = 9090
        protocol      = "tcp"
      },
      {
        containerPort = 2049
        hostPort      = 2049
        protocol      = "tcp"
      }
    ]
    healthCheck = {
      command  = ["CMD-SHELL", "curl -f http://localhost:9090/health"]
      interval = 30
      retries  = 10
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
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

resource "aws_security_group_rule" "ingress_from_server_service_alb_to_efs" {
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.example_server_app_alb.id
  security_group_id        = data.aws_security_group.vpc_default.id
}

resource "aws_security_group_rule" "ingress_from_efs_to_server_service_alb" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.efs.id
  security_group_id        = aws_security_group.example_server_app_alb.id
}

#resource "aws_security_group_rule" "eggress_from_efs_to_server_service_alb" {
#  type                     = "egress"
#  from_port                = 2049
#  to_port                  = 2049
#  protocol                 = "-1"
#  source_security_group_id = aws_security_group.example_server_app_alb.id
#  security_group_id        = aws_security_group.efs.id
#}

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

resource "consul_service" "external_server_service" {
  depends_on = [module.dc1]
  name       = "${var.name}-external-server-app"
  node       = consul_node.external_node.name
  port       = 9090
  provider   = consul.dc1-cluster
}

resource "consul_node" "external_node" {
  depends_on = [module.dc1]
  name       = "${var.name}_external_server_app_node"
  address    = aws_lb.example_server_app.dns_name
  meta = {
    "external-node" = "true"
  }
  provider = consul.dc1-cluster
}

resource "consul_config_entry" "external_service_intentions" {
  depends_on = [module.dc1]
  name       = "${var.name}-external-server-app"
  kind       = "service-intentions"

  config_json = jsonencode({
    Sources = [
      {
        Name   = "${var.name}-example-client-app"
        Action = "allow"
      }
    ]
  })

  provider = consul.dc1-cluster
}

resource "consul_config_entry" "terminating_gateway_entry" {
  name = "${var.name}-terminating-gateway"
  kind = "terminating-gateway"

  config_json = jsonencode({
    Services = [{ Name = "${var.name}-external-server-app" }]
  })

  provider = consul.dc1-cluster
}

resource "consul_acl_policy" "external_server_app_policy" {
  name  = "external_server_app_write_policy"
  rules = <<-RULE
    service "${var.name}-external-server-app" {
      policy = "write"
    }
    RULE

  provider = consul.dc1-cluster
}

# A null_resource to introduce an arbitrary delay. This is
# done to make sure that the ECS controller has already
# created the required consul-ecs-terminating-gateway-role.
# Sleeping for 60 seconds might not all be needed but
# it is just added to completely ensure that the role is present
# in Consul.
resource "null_resource" "arbitrary_delay" {
  depends_on = [module.ecs_controller]
  triggers = {
    force_recreate = timestamp()
  }

  provisioner "local-exec" {
    command = "sleep 60"
  }
}

data "consul_acl_role" "ecs_terminating_gateway_default_role" {
  depends_on = [null_resource.arbitrary_delay]
  name       = "consul-ecs-terminating-gateway-role"

  provider = consul.dc1-cluster
}

resource "consul_acl_role_policy_attachment" "external_server_app_role_policy_attachment" {
  role_id = data.consul_acl_role.ecs_terminating_gateway_default_role.id
  policy  = consul_acl_policy.external_server_app_policy.name

  provider = consul.dc1-cluster
}


resource "aws_iam_role" "this_task" {
  name = "${var.name}-external-server-app-role2"
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
            "ssmmessages:OpenDataChannel",
            "ssm:StartSession",
            "ssm:GetConnectionStatus",
            "ssm:DescribeSessions",
            "ssm:DescribeInstanceProperties",
            "ssm:TerminateSession",
            "elasticfilesystem:ClientRootAccess",
            "elasticfilesystem:ClientMount",
            "elasticfilesystem:ClientWrite",
            "ecs:ListTasks",
            "ecs:DescribeTasks",
          ]
          Resource = "*"
        },
      ]
    })
  }
}



resource "aws_iam_policy" "this_execution" {
  name        = "${var.name}-external-server-app-policy"
  path        = "/ecs/"
  description = "log execution policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "elasticfilesystem:ClientRootAccess",
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "this_execution" {
  name = "${var.name}-external-server-app-execution"
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

resource "aws_iam_role_policy_attachment" "external-server-app-execution" {
  role       = aws_iam_role.this_execution.id
  policy_arn = aws_iam_policy.this_execution.arn
}