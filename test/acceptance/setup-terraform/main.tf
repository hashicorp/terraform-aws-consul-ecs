# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

locals {
  name   = "consul-ecs-${random_string.suffix.result}"
  suffix = random_string.suffix.result

  cluster_count = 3
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

resource "random_shuffle" "azs" {
  input = data.aws_availability_zones.available.names
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = local.name
  cidr = "10.0.0.0/16"
  // The NAT gateway limit is per AZ. With `single_nat_gateway = true`, the NAT gateway is created
  // in the first public subnet. Shuffling AZs helps spread NAT gateways across AZs to help with this.
  azs = [
    // Silly, but avoids this error: `"count" value depends on resource attributes that cannot be determined until apply`
    random_shuffle.azs.result[0],
    random_shuffle.azs.result[1],
    random_shuffle.azs.result[2],
  ]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  tags                 = var.tags
}

// Create ECS clusters
// The clusters are created in the same VPC to ensure there is network connectivity between them.
resource "aws_ecs_cluster" "clusters" {
  count = local.cluster_count

  name = "${local.name}-${count.index}"
  tags = var.tags
}

// We use a capacity provider for FARGATE only. We don't use a capacity provider for EC2. Instead, we spin up EC2 instances directly in Terraform.
resource "aws_ecs_cluster_capacity_providers" "clusters" {
  // If FARGATE enabled, create one for each cluster.
  count = var.launch_type == "FARGATE" ? local.cluster_count : 0

  cluster_name       = aws_ecs_cluster.clusters[count.index].name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = var.launch_type
  }
}

// Create ec2 instances for each cluster for the EC2 launch type.
module "ec2" {
  count  = var.launch_type == "EC2" ? local.cluster_count : 0
  source = "./ec2"

  ecs_cluster_name = aws_ecs_cluster.clusters[count.index].name
  instance_count   = var.instance_count
  instance_type    = var.instance_type
  name             = "${local.name}-${count.index}"
  tags             = var.tags
  vpc              = module.vpc
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = local.name
  tags = var.tags
}

module "hcp" {
  count  = var.enable_hcp ? 1 : 0
  source = "./hcp"

  region         = var.region
  suffix         = local.suffix
  vpc            = module.vpc
  consul_version = var.consul_version
}

resource "aws_security_group_rule" "cluster_egress" {
  description              = "Access to endpoints outside the VPC"
  type                     = "egress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  cidr_blocks              = ["0.0.0.0/0"]
  security_group_id        = module.vpc.default_security_group_id
}
