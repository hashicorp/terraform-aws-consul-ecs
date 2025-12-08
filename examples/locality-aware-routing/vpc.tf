# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

locals {
  // both VPCs use the same overlapping subnet addresses
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs  = ["10.0.3.0/24", "10.0.4.0/24"]
}

data "aws_availability_zones" "available_region" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.11.3"

  name                 = var.name
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available_region.names
  private_subnets      = local.private_subnet_cidrs
  public_subnets       = local.public_subnet_cidrs
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
}