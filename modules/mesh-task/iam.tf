# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  execution_role_id = var.create_execution_role ? aws_iam_role.execution[0].id : lookup(var.execution_role, "id", null)
  task_role_id      = var.create_task_role ? aws_iam_role.task[0].id : lookup(var.task_role, "id", null)
  // We need the ARN for the task definition.
  execution_role_arn = var.create_execution_role ? aws_iam_role.execution[0].arn : lookup(var.execution_role, "arn", null)
  task_role_arn      = var.create_task_role ? aws_iam_role.task[0].arn : lookup(var.task_role, "arn", null)
}

// Create the task role if create_task_role=true
resource "aws_iam_role" "task" {
  count = var.create_task_role ? 1 : 0
  path  = var.iam_role_path

  name = "${var.family}-task"
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

  tags = {
    "consul.hashicorp.com.service-name" = local.service_name
    "consul.hashicorp.com.namespace"    = var.consul_namespace
  }
}

// If acls are enabled, the task role must be configured with an `iam:GetRole` permission
// to fetch itself, in order to be compatbile with the auth method.
//
// Only create this if create_task_role=true
resource "aws_iam_policy" "task" {
  count       = var.acls && var.create_task_role ? 1 : 0
  name        = "${var.family}-task"
  path        = var.iam_role_path
  description = "${var.family} mesh-task task policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:GetRole"
      ],
      "Resource": [
        "${local.task_role_arn}"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "task" {
  count      = var.acls && var.create_task_role ? 1 : 0
  role       = local.task_role_id
  policy_arn = aws_iam_policy.task[count.index].arn
}

// Only attach extra policies if create_task_role=true.
// We have a validation to ensure additional_task_role_policies can only
// be passed when var.create_task_role=true.
resource "aws_iam_role_policy_attachment" "additional_task_policies" {
  count      = var.create_task_role ? length(var.additional_task_role_policies) : 0
  role       = local.task_role_id
  policy_arn = var.additional_task_role_policies[count.index]
}

// Create the execution role if var.create_execution_role=true
resource "aws_iam_role" "execution" {
  count = var.create_execution_role ? 1 : 0
  name  = "${var.family}-execution"
  path  = var.iam_role_path

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

// Only create and attach this policy if var.create_execution_role=true
resource "aws_iam_policy" "execution" {
  count       = var.create_execution_role ? 1 : 0
  name        = "${var.family}-execution"
  path        = var.iam_role_path
  description = "${var.family} mesh-task execution policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
%{if var.tls~}
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
%{endif~}
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
        "Action": [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage"
        ],
        "Effect": "Allow",
        "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "execution" {
  count      = var.create_execution_role ? 1 : 0
  role       = local.execution_role_id
  policy_arn = aws_iam_policy.execution[count.index].arn
}

// Only attach extra policies if create_execution_role=true.
// We have a validation to ensure additional_execution_role_policies can only
// be passed when var.create_execution_role=true.
resource "aws_iam_role_policy_attachment" "additional_execution_policies" {
  count      = var.create_execution_role ? length(var.additional_execution_role_policies) : 0
  role       = local.execution_role_id
  policy_arn = var.additional_execution_role_policies[count.index]
}