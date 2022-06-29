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
  path  = "/ecs/"

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
  path        = "/ecs/"
  description = "${var.family} mesh-task execution policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
%{if var.tls~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${var.consul_server_ca_cert_arn}"
      ]
    },
%{endif~}
%{if var.acls~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${var.consul_client_token_secret_arn}",
        "${aws_secretsmanager_secret.service_token[0].arn}"
      ]
    },
%{endif~}
%{if local.gossip_encryption_enabled~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${var.gossip_key_secret_arn}"
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
