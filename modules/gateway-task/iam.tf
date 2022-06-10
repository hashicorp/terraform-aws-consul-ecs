locals {
  // We use a splat trick to workaround a Terraform limitation: `The "count" value
  // depends on resource attributes that cannot be determined until apply`
  //
  // Basically, users will pass in the output value of another resource. That resource
  // may not be created during the planning phase, so Terraform cannot inspect the value
  // to set a `count` field. So it errors.
  //
  // The workaround uses a splat to convert to 1-length or 0-length list.
  //
  // "If the value is anything other than a null value then the splat expression will transform
  // it into a single-element list...If the value is null then the splat expression will return
  // an empty tuple."
  // https://www.terraform.io/docs/language/expressions/splat.html#single-values-as-lists
  create_task_role      = length(var.task_role[*]) == 0 ? true : length(var.task_role.id[*]) == 0
  create_execution_role = length(var.execution_role[*]) == 0 ? true : length(var.execution_role.id[*]) == 0

  execution_role_id = local.create_execution_role ? aws_iam_role.execution[0].id : var.execution_role.id
  task_role_id      = local.create_task_role ? aws_iam_role.task[0].id : var.task_role.id
  // We need the ARN for the task definition.
  execution_role_arn = local.create_execution_role ? aws_iam_role.execution[0].arn : var.execution_role.arn
  task_role_arn      = local.create_task_role ? aws_iam_role.task[0].arn : var.task_role.arn
}

// Create the task role
resource "aws_iam_role" "task" {
  count = local.create_task_role ? 1 : 0
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
#    "consul.hashicorp.com.partition"    = var.consul_partition
  }
}

// If acls are enabled, the task role must be configured with an `iam:GetRole` permission
// to fetch itself, in order to be compatbile with the auth method.
resource "aws_iam_policy" "task" {
  count       = var.acls ? 1 : 0
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
  count      = var.acls ? 1 : 0
  role       = local.task_role_id
  policy_arn = aws_iam_policy.task[count.index].arn
}

resource "aws_iam_role_policy_attachment" "additional_task_policies" {
  count      = length(var.additional_task_role_policies)
  role       = local.task_role_id
  policy_arn = var.additional_task_role_policies[count.index]
}

// Create the execution role and attach policies
resource "aws_iam_role" "execution" {
  count = local.create_execution_role ? 1 : 0
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

resource "aws_iam_policy" "execution" {
  name        = "${var.family}-execution"
  path        = var.iam_role_path
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
  role       = local.execution_role_id
  policy_arn = aws_iam_policy.execution.arn
}

resource "aws_iam_role_policy_attachment" "additional_execution_policies" {
  count      = length(var.additional_execution_role_policies)
  role       = local.execution_role_id
  policy_arn = var.additional_execution_role_policies[count.index]
}
