data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_kms_alias" "secretsmanager" {
  name = "alias/aws/secretsmanager"
}

locals {
  datacenter = "dc1"
}

# ---------------------------------------------------------------------------------------------------------------------
# Create VPC with public and also private subnets
# ---------------------------------------------------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.21.0"

  name               = var.name
  cidr               = var.vpc_cidr
  azs                = var.vpc_az
  public_subnets     = var.public_subnet_cidrs
  private_subnets    = var.private_subnet_cidrs
  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  # Specifically for EFS mount via dns feature
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_ecs_cluster" "ecs" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

module "consul-cluster" {
  source = "../../modules/ha-cluster"
  # version = ""

  name               = "consul"
  datacenter         = local.datacenter
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
  public_subnet_ids  = module.vpc.public_subnets

  lb_enabled                  = true
  internal_alb_listener       = true
  lb_ingress_rule_cidr_blocks = var.lb_ingress_rule_cidr_blocks
  lb_ingress_rule_security_groups = compact(concat(
    var.lb_ingress_rule_security_groups,
    [module.k6lambda.security_group_id]
  ))

  ecs_cluster_name = aws_ecs_cluster.ecs.name

  consul_image              = var.consul_image
  operating_system_family   = var.operating_system_family
  cpu_architecture          = var.cpu_architecture
  docker_username           = var.docker_username
  docker_password           = var.docker_password
  consul_count              = var.consul_count
  gossip_encryption_enabled = true
  acls                      = false # acl disabled for the load test
  # otherwise need to distribute agent tokens and policy

  # The certificates must exist in your codebase. See GNUmakefile for more about certs.
  tls = true
}
