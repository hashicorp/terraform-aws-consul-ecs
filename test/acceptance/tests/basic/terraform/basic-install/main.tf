variable "ecs_cluster_arn" {
  type        = string
  description = "Cluster ARN of ECS cluster."
}

variable "vpc_id" {
  description = "The ID of the VPC for all resources."
  type        = string
}

variable "subnets" {
  type        = list(string)
  description = "Subnets to deploy into."
}

variable "suffix" {
  type        = string
  default     = "nosuffix"
  description = "Suffix to add to all resource names."
}

variable "region" {
  type        = string
  description = "Region."
}

variable "log_group_name" {
  type        = string
  description = "Name for cloudwatch log group."
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "secure" {
  description = "Whether to create all resources in a secure installation (with TLS, ACLs and gossip encryption)."
  type        = bool
  default     = false
}

variable "launch_type" {
  description = "Whether to launch tasks on Fargate or EC2"
  type        = string
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:latest"
}

variable "server_service_name" {
  description = "The service name for the test_server"
  type        = string
}

provider "aws" {
  region = var.region
}

// Generate a gossip encryption key if a secure installation.
resource "random_id" "gossip_encryption_key" {
  count       = var.secure ? 1 : 0
  byte_length = 32
}

resource "aws_secretsmanager_secret" "gossip_key" {
  count = var.secure ? 1 : 0
  // Only 'consul_server*' secrets are allowed by the IAM role used by Circle CI
  name = "consul_server_${var.suffix}-gossip-encryption-key"
}

resource "aws_secretsmanager_secret_version" "gossip_key" {
  count         = var.secure ? 1 : 0
  secret_id     = aws_secretsmanager_secret.gossip_key[0].id
  secret_string = random_id.gossip_encryption_key[0].b64_std
}

module "consul_server" {
  source          = "../../../../../../modules/dev-server"
  lb_enabled      = false
  ecs_cluster_arn = var.ecs_cluster_arn
  subnet_ids      = var.subnets
  vpc_id          = var.vpc_id
  name            = "consul_server_${var.suffix}"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul_server_${var.suffix}"
    }
  }
  launch_type                 = var.launch_type
  service_discovery_namespace = "consul-${var.suffix}"

  tags = var.tags

  tls                   = var.secure
  gossip_key_secret_arn = var.secure ? aws_secretsmanager_secret.gossip_key[0].arn : ""
  acls                  = var.secure
}

data "aws_security_group" "vpc_default" {
  vpc_id = var.vpc_id

  filter {
    name   = "group-name"
    values = ["default"]
  }
}

resource "aws_security_group_rule" "consul_server_ingress" {
  description              = "Access to Consul dev server from default security group"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = data.aws_security_group.vpc_default.id
  security_group_id        = module.consul_server.security_group_id
}

module "acl_controller" {
  count  = var.secure ? 1 : 0
  source = "../../../../../../modules/acl-controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller"
    }
  }
  launch_type                       = var.launch_type
  consul_bootstrap_token_secret_arn = module.consul_server.bootstrap_token_secret_arn
  consul_server_http_addr           = "https://${module.consul_server.server_dns}:8501"
  consul_server_ca_cert_arn         = module.consul_server.ca_cert_arn
  ecs_cluster_arn                   = var.ecs_cluster_arn
  region                            = var.region
  subnets                           = var.subnets
  name_prefix                       = var.suffix
  consul_ecs_image                  = var.consul_ecs_image
}

resource "aws_ecs_service" "test_client" {
  name            = "test_client_${var.suffix}"
  cluster         = var.ecs_cluster_arn
  task_definition = module.test_client.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.subnets
  }
  launch_type            = var.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "test_client_${var.suffix}"
  container_definitions = [
    {
      name             = "basic"
      image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
      essential        = true
      logConfiguration = local.test_client_log_configuration
      environment = [
        {
          name  = "UPSTREAM_URIS"
          value = "http://localhost:1234"
        }
      ]
      linuxParameters = {
        initProcessEnabled = true
      }
      command = ["/app/fake-service"]
      healthCheck = {
        command  = ["CMD-SHELL", "echo 1"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
    },
    {
      # Inject an additional container to monitor apps during task shutdown.
      name             = "shutdown-monitor"
      image            = "docker.mirror.hashicorp.services/golang:1.17-alpine"
      essential        = false
      logConfiguration = local.test_client_log_configuration
      # AWS: "We do not enforce a size limit on the environment variables..."
      # Then, the max environment var length is ~32k
      environment = [{
        name  = "GOLANG_MAIN_B64"
        value = base64encode(file("${path.module}/shutdown-monitor.go"))
      }]
      # NOTE: `go run <file>` signal handling is different: https://github.com/golang/go/issues/40467
      entryPoint = ["/bin/sh", "-c", <<EOT
echo "$GOLANG_MAIN_B64" | base64 -d > main.go
go build main.go
exec ./main
EOT
      ]
    }
  ]
  retry_join = [module.consul_server.server_dns]
  upstreams = [
    {
      destination_name = "${var.server_service_name}_${var.suffix}"
      local_bind_port  = 1234
    }
  ]
  log_configuration = local.test_client_log_configuration
  outbound_only     = true
  // This keeps the application running for 10 seconds.
  application_shutdown_delay_seconds = 10

  tls                            = var.secure
  consul_server_ca_cert_arn      = module.consul_server.ca_cert_arn
  gossip_key_secret_arn          = var.secure ? aws_secretsmanager_secret.gossip_key[0].arn : ""
  acls                           = var.secure
  consul_client_token_secret_arn = var.secure ? module.acl_controller[0].client_token_secret_arn : ""
  acl_secret_name_prefix         = var.suffix
  consul_ecs_image               = var.consul_ecs_image

  additional_task_role_policies = [aws_iam_policy.execute-command.arn]
}

resource "aws_ecs_service" "test_server" {
  name            = "test_server_${var.suffix}"
  cluster         = var.ecs_cluster_arn
  task_definition = module.test_server.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.subnets
  }
  launch_type            = var.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "test_server" {
  source              = "../../../../../../modules/mesh-task"
  family              = "test_server_${var.suffix}"
  consul_service_name = "${var.server_service_name}_${var.suffix}"
  container_definitions = [{
    name             = "basic"
    image            = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential        = true
    logConfiguration = local.test_server_log_configuration
  }]
  retry_join        = [module.consul_server.server_dns]
  log_configuration = local.test_server_log_configuration
  checks = [
    {
      checkid  = "server-http"
      name     = "HTTP health check on port 9090"
      http     = "http://localhost:9090/health"
      method   = "GET"
      timeout  = "10s"
      interval = "2s"
    }
  ]
  port = 9090

  tls                            = var.secure
  consul_server_ca_cert_arn      = module.consul_server.ca_cert_arn
  gossip_key_secret_arn          = var.secure ? aws_secretsmanager_secret.gossip_key[0].arn : ""
  acls                           = var.secure
  consul_client_token_secret_arn = var.secure ? module.acl_controller[0].client_token_secret_arn : ""
  acl_secret_name_prefix         = var.suffix
  consul_ecs_image               = var.consul_ecs_image

  // Test passing both a role resource and role data source objects to make sure both
  // have the necessary fields ("arn" and "id").
  task_role                     = aws_iam_role.task
  execution_role                = aws_iam_role.execution
  additional_task_role_policies = [aws_iam_policy.execute-command.arn]
}

// Testing passing task/execution role into mesh-task
resource "aws_iam_role" "task" {
  name = "test_server_${var.suffix}_task_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}


// Policy to allow `aws execute-command`
resource "aws_iam_policy" "execute-command" {
  name   = "ecs-execute-command-${var.suffix}"
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

  # TODO: don't have permission to add tags
  # tags = var.tags
}

resource "aws_iam_role" "execution" {
  name = "test_server_${var.suffix}_execution_role"
  path = "/ecs/"

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

locals {
  test_server_log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "test_server_${var.suffix}"
    }
  }

  test_client_log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "test_client_${var.suffix}"
    }
  }
}
