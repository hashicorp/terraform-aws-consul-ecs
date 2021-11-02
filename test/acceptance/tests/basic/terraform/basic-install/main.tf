provider "aws" {
  region = var.region
}

// Generate a gossip encryption key if a secure installation.
resource "random_id" "gossip_encryption_key" {
  count       = var.secure ? 1 : 0
  byte_length = 32
}

# Find our public IP to restrict ingress to the ALB.
# NOTE: Produces a warning because checkip.amazonaws.com does not return a Content-Type header.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

locals {
  ingress_ip = trimspace(data.http.my_ip.body)
  consul_server_http_addr = (var.secure ?
    "https://${module.consul_server.lb_dns_name}:8501" :
  "http://${module.consul_server.lb_dns_name}:8500")
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

data "aws_security_group" "vpc_default" {
  name   = "default"
  vpc_id = var.vpc_id
}

module "consul_server" {
  source = "../../../../../../modules/dev-server"
  // Note: The ALB takes a few minutes to spin up. We may want to move this
  // into setup-terraform if we have several cases of basic-install/TestBasic.
  lb_enabled                  = true
  lb_subnets                  = var.public_subnets
  lb_ingress_rule_cidr_blocks = ["${local.ingress_ip}/32"]
  ecs_cluster_arn             = var.ecs_cluster_arn
  subnet_ids                  = var.private_subnets
  vpc_id                      = var.vpc_id
  name                        = "consul_server_${var.suffix}"
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


resource "aws_security_group_rule" "ingress_from_server_alb_to_ecs" {
  type                     = "ingress"
  from_port                = 8500
  to_port                  = 8500
  protocol                 = "tcp"
  source_security_group_id = module.consul_server.lb_security_group_id
  security_group_id        = data.aws_security_group.vpc_default.id
}

module "common" {
  source = "../../../../common-terraform"

  ecs_cluster_arn                   = var.ecs_cluster_arn
  private_subnets                   = var.private_subnets
  suffix                            = var.suffix
  region                            = var.region
  log_group_name                    = var.log_group_name
  tags                              = var.tags
  launch_type                       = var.launch_type
  consul_ecs_image                  = var.consul_ecs_image
  retry_join                        = module.consul_server.server_dns
  consul_server_http_addr           = module.consul_server.lb_dns_name
  secure                            = var.secure
  consul_server_ca_cert_arn         = var.secure ? module.consul_server.ca_cert_arn : ""
  consul_bootstrap_token_secret_arn = var.secure ? module.consul_server.bootstrap_token_secret_arn : ""
  consul_gossip_key_secret_arn      = var.secure ? aws_secretsmanager_secret.gossip_key[0].arn : ""
  server_service_name               = var.server_service_name
}
