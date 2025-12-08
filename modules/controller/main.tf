# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

locals {
  https_ca_cert_arn = var.consul_https_ca_cert_arn != "" ? var.consul_https_ca_cert_arn : var.consul_ca_cert_arn
  grpc_ca_cert_arn  = var.consul_grpc_ca_cert_arn != "" ? var.consul_grpc_ca_cert_arn : var.consul_ca_cert_arn
}

resource "aws_ecs_service" "this" {
  name            = "consul-ecs-controller"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  network_configuration {
    subnets          = var.subnets
    security_groups  = var.security_groups
    assign_public_ip = var.assign_public_ip
  }
  launch_type            = var.launch_type
  enable_execute_command = true
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-consul-ecs-controller"
  requires_compatibilities = var.requires_compatibilities
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  task_role_arn            = aws_iam_role.this_task.arn
  execution_role_arn       = aws_iam_role.this_execution.arn
  container_definitions = jsonencode([
    {
      name             = "consul-ecs-controller"
      image            = var.consul_ecs_image
      essential        = true
      logConfiguration = var.log_configuration,
      command          = ["controller"]
      linuxParameters = {
        initProcessEnabled = true
      }
      secrets = concat([
        {
          name      = "CONSUL_HTTP_TOKEN"
          valueFrom = var.consul_bootstrap_token_secret_arn
        }],
        local.grpc_ca_cert_arn != "" ? [
          {
            name      = "CONSUL_GRPC_CACERT_PEM"
            valueFrom = local.grpc_ca_cert_arn
          }
        ] : [],
        local.https_ca_cert_arn != "" ? [
          {
            name      = "CONSUL_HTTPS_CACERT_PEM"
            valueFrom = local.https_ca_cert_arn
          }
        ] : [],
      )
      environment = [
        {
          name  = "CONSUL_ECS_CONFIG_JSON"
          value = local.encoded_config
        }
      ]
      readonlyRootFilesystem = true
    },
  ])
}

resource "aws_iam_role" "this_task" {
  name = "${var.name_prefix}-consul-ecs-controller-task"
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
  name        = "${var.name_prefix}-consul-ecs-controller-execution"
  path        = "/ecs/"
  description = "Consul controller execution"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${var.consul_bootstrap_token_secret_arn}"
      ]
    },
%{if var.consul_ca_cert_arn != ""~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${var.consul_ca_cert_arn}"
      ]
    },
%{endif~}
%{if var.consul_https_ca_cert_arn != ""~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${var.consul_https_ca_cert_arn}"
      ]
    },
%{endif~}
%{if var.consul_grpc_ca_cert_arn != ""~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${var.consul_grpc_ca_cert_arn}"
      ]
    },
%{endif~}
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

resource "aws_iam_role" "this_execution" {
  name = "${var.name_prefix}-consul-ecs-controller-execution"
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

resource "aws_iam_role_policy_attachment" "consul-controller-execution" {
  role       = aws_iam_role.this_execution.id
  policy_arn = aws_iam_policy.this_execution.arn
}

resource "aws_iam_role_policy_attachment" "additional_execution_policies" {
  count      = length(var.additional_execution_role_policies)
  role       = aws_iam_role.this_execution.id
  policy_arn = var.additional_execution_role_policies[count.index]
}