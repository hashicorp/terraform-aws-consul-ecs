resource "aws_secretsmanager_secret" "client_token" {
  name = "${var.name_prefix}-consul-client-token"
}

resource "aws_secretsmanager_secret_version" "client_token" {
  secret_id     = aws_secretsmanager_secret.client_token.id
  secret_string = jsonencode({})
}

resource "aws_ecs_service" "this" {
  name            = "consul-acl-controller"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  network_configuration {
    subnets = var.subnets
  }
  launch_type            = var.launch_type
  enable_execute_command = true
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-consul-acl-controller"
  requires_compatibilities = var.requires_compatibilities
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  task_role_arn            = aws_iam_role.this_task.arn
  execution_role_arn       = aws_iam_role.this_execution.arn
  container_definitions = jsonencode([
    {
      name             = "consul-acl-controller"
      image            = var.consul_ecs_image
      essential        = true
      logConfiguration = var.log_configuration,
      command = [
        "controller",
        "-consul-client-secret-arn", aws_secretsmanager_secret.client_token.arn,
        "-secret-name-prefix", var.name_prefix,
      ]
      linuxParameters = {
        initProcessEnabled = true
      }
      secrets = concat([
        {
          name      = "CONSUL_HTTP_TOKEN",
          valueFrom = var.consul_bootstrap_token_secret_arn
        }],
        var.consul_server_ca_cert_arn != "" ? [
          {
            name      = "CONSUL_CACERT_PEM",
            valueFrom = var.consul_server_ca_cert_arn
          }
      ] : [])
      environment = [
        {
          name  = "CONSUL_HTTP_ADDR"
          value = var.consul_server_http_addr
        }
      ]
    },
  ])
}

resource "aws_iam_role" "this_task" {
  name = "${var.name_prefix}-consul-acl-controller-task"
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
        {
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue",
            "secretsmanager:UpdateSecret"
          ]
          Resource = "arn:aws:secretsmanager:${var.region}:*:secret:${var.name_prefix}-*"
        }
      ]
    })
  }
}

resource "aws_iam_policy" "this_execution" {
  name        = "${var.name_prefix}-consul-acl-controller-execution"
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
%{if var.consul_server_ca_cert_arn != ""~}
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
  name = "${var.name_prefix}-consul-acl-controller-execution"
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
