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

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:latest"
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
  launch_type = "FARGATE"

  tags = var.tags

  tls                   = var.secure
  gossip_key_secret_arn = var.secure ? aws_secretsmanager_secret.gossip_key[0].arn : ""
  acls                  = var.secure
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
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "test_client_${var.suffix}"
  container_definitions = [{
    name      = "basic"
    image     = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential = true
    environment = [
      {
        name  = "UPSTREAM_URIS"
        value = "http://localhost:1234"
      }
    ]
    linuxParameters = {
      initProcessEnabled = true
    }
  }]
  retry_join = module.consul_server.server_dns
  upstreams = [
    {
      destination_name = "test_server_${var.suffix}"
      local_bind_port  = 1234
    }
  ]
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "test_client_${var.suffix}"
    }
  }
  outbound_only = true

  tls                            = var.secure
  consul_server_ca_cert_arn      = module.consul_server.ca_cert_arn
  gossip_key_secret_arn          = var.secure ? aws_secretsmanager_secret.gossip_key[0].arn : ""
  acls                           = var.secure
  consul_client_token_secret_arn = var.secure ? module.acl_controller[0].client_token_secret_arn : ""
  acl_secret_name_prefix         = var.suffix
  consul_ecs_image               = var.consul_ecs_image
}

resource "aws_ecs_service" "test_server" {
  name            = "test_server_${var.suffix}"
  cluster         = var.ecs_cluster_arn
  task_definition = module.test_server.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "test_server" {
  source = "../../../../../../modules/mesh-task"
  family = "test_server_${var.suffix}"
  container_definitions = [{
    name      = "basic"
    image     = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential = true
  }]
  retry_join = module.consul_server.server_dns
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "test_server_${var.suffix}"
    }
  }
  port = 9090

  tls                            = var.secure
  consul_server_ca_cert_arn      = module.consul_server.ca_cert_arn
  gossip_key_secret_arn          = var.secure ? aws_secretsmanager_secret.gossip_key[0].arn : ""
  acls                           = var.secure
  consul_client_token_secret_arn = var.secure ? module.acl_controller[0].client_token_secret_arn : ""
  acl_secret_name_prefix         = var.suffix
  consul_ecs_image               = var.consul_ecs_image
}
