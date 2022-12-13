variable "ecs_cluster_arn" {
  type        = string
  description = "ARN of ECS cluster."
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


variable "consul_license" {
  description = "A Consul Enterprise license key. Requires consul_image to be set to a Consul Enterprise image."
  type        = string
  default     = ""
  sensitive   = true
}

variable "consul_image" {
  type    = string
  default = ""
}

variable "launch_type" {
  description = "Whether to launch tasks on Fargate or EC2"
  type        = string
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "docker.mirror.hashicorp.services/hashicorppreview/consul-ecs:0.5.2-dev"
}

variable "server_service_name" {
  description = "The service name for the test_server"
  type        = string
}

variable "consul_datacenter" {
  description = "The consul datacenter name. Should be unique among parallel test cases to ensure a unique Cloud Map namespace."
  type        = string
}

provider "aws" {
  region = var.region
}

locals {
  enterprise_enabled = var.consul_license != ""
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
  launch_type = var.launch_type

  tags = var.tags

  tls                            = var.secure
  gossip_encryption_enabled      = var.secure
  generate_gossip_encryption_key = false
  gossip_key_secret_arn          = var.secure ? aws_secretsmanager_secret.gossip_key[0].arn : ""
  acls                           = var.secure

  service_discovery_namespace = var.consul_datacenter
  datacenter                  = var.consul_datacenter
  consul_image                = var.consul_image
  consul_license              = var.consul_license
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
  consul_partitions_enabled         = local.enterprise_enabled
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
  // mesh-task will lower case this to `test_client_<suffix>` for the service name.
  family = "Test_Client_${var.suffix}"
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
      linuxParameters = {
        initProcessEnabled = true
      }
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
      destinationName = "${var.server_service_name}_${var.suffix}"
      localBindPort   = 1234
    }
  ]
  log_configuration = local.test_client_log_configuration
  outbound_only     = true
  // This keeps the application running for 10 seconds.
  application_shutdown_delay_seconds = 10
  // Test with a port other than the default of 20000.
  envoy_public_listener_port = 21000

  tls                       = var.secure
  consul_server_ca_cert_arn = var.secure ? module.consul_server.ca_cert_arn : ""
  gossip_key_secret_arn     = var.secure ? aws_secretsmanager_secret.gossip_key[0].arn : ""
  acls                      = var.secure
  consul_ecs_image          = var.consul_ecs_image
  consul_image              = var.consul_image

  additional_task_role_policies = [aws_iam_policy.execute-command.arn]

  consul_http_addr = var.secure ? "https://${module.consul_server.server_dns}:8501" : ""
  # For dev-server, the server_ca_cert (internal rpc) and the https ca cert are the same.
  # But, they are different in HCP.
  consul_https_ca_cert_arn = var.secure ? module.consul_server.ca_cert_arn : ""

  consul_agent_configuration = <<-EOT
  log_level = "debug"
  EOT

  consul_datacenter = var.consul_datacenter
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
      checkId  = "server-http"
      name     = "HTTP health check on port 9090"
      http     = "http://localhost:9090/health"
      method   = "GET"
      timeout  = "10s"
      interval = "2s"
    }
  ]
  port = 9090

  tls                       = var.secure
  consul_server_ca_cert_arn = var.secure ? module.consul_server.ca_cert_arn : ""
  gossip_key_secret_arn     = var.secure ? aws_secretsmanager_secret.gossip_key[0].arn : ""
  acls                      = var.secure
  consul_ecs_image          = var.consul_ecs_image
  consul_image              = var.consul_image

  consul_http_addr         = var.secure ? "https://${module.consul_server.server_dns}:8501" : ""
  consul_https_ca_cert_arn = var.secure ? module.consul_server.ca_cert_arn : ""

  // Test passing in roles. This requires users to correctly configure the roles outside mesh-task.
  create_task_role      = false
  create_execution_role = false
  task_role             = aws_iam_role.task
  execution_role        = aws_iam_role.execution

  consul_datacenter = var.consul_datacenter
}

// Configure a task role for passing in to mesh-task.
resource "aws_iam_role" "task" {
  name = "test_server_${var.suffix}_task_role"
  path = "/consul-ecs/"

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

  // Terraform does not support managing individual tags for IAM roles yet.
  // These tags must be set when a role is passed in to mesh-task, if acls are enabled.
  tags = {
    "consul.hashicorp.com.service-name" = "${var.server_service_name}_${var.suffix}"
    "consul.hashicorp.com.namespace"    = ""
  }
}

// Policy to allow iam:GetRole (required for auth method)
resource "aws_iam_policy" "get-task-role" {
  count = var.secure ? 1 : 0
  name  = "test_server_${var.suffix}_get_task_role_policy"
  path  = "/consul-ecs/"

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

resource "aws_iam_role_policy_attachment" "get-task-role" {
  count      = var.secure ? 1 : 0
  role       = aws_iam_role.task.id
  policy_arn = aws_iam_policy.get-task-role[count.index].arn
}

// Policy to allow `aws execute-command`
resource "aws_iam_policy" "execute-command" {
  name   = "ecs-execute-command-${var.suffix}"
  path   = "/consul-ecs/"
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

resource "aws_iam_role_policy_attachment" "execute-command" {
  role       = aws_iam_role.task.id
  policy_arn = aws_iam_policy.execute-command.arn
}

resource "aws_iam_role" "execution" {
  name = "test_server_${var.suffix}_execution_role"
  path = "/consul-ecs/"

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

  inline_policy {
    name   = "test_server_${var.suffix}_execution_role_policy"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
%{if var.secure~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${module.consul_server.ca_cert_arn}",
        "${aws_secretsmanager_secret.gossip_key[0].arn}"
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
