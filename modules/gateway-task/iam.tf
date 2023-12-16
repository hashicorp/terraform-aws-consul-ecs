# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

// Create the task role
resource "aws_iam_role" "task" {
  path = var.iam_role_path

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
    "consul.hashicorp.com.namespace"    = local.consul_namespace
    "consul.hashicorp.com.gateway-kind" = var.kind
  }
}

// If acls are enabled, the task role must be configured with an `iam:GetRole` permission
// to fetch itself, in order to be compatbile with the auth method.
resource "aws_iam_policy" "task" {
  count       = var.acls ? 1 : 0
  name        = "${var.family}-task"
  path        = var.iam_role_path
  description = "${var.family} gateway-task task policy"

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
        "${aws_iam_role.task.arn}"
      ]
    }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "task" {
  count      = var.acls ? 1 : 0
  role       = aws_iam_role.task.id
  policy_arn = aws_iam_policy.task[count.index].arn
}

resource "aws_iam_role_policy_attachment" "additional_task_policies" {
  count      = length(var.additional_task_role_policies)
  role       = aws_iam_role.task.id
  policy_arn = var.additional_task_role_policies[count.index]
}

// Create the execution role and attach policies
resource "aws_iam_role" "execution" {
  name = "${var.family}-execution"
  path = var.iam_role_path

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

resource "aws_iam_policy" "execution" {
  name        = "${var.family}-execution"
  path        = var.iam_role_path
  description = "${var.family} gateway-task execution policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
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

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.id
  policy_arn = aws_iam_policy.execution.arn
}

resource "aws_iam_role_policy_attachment" "additional_execution_policies" {
  count      = length(var.additional_execution_role_policies)
  role       = aws_iam_role.execution.id
  policy_arn = var.additional_execution_role_policies[count.index]
}
