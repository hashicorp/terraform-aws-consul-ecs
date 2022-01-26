locals {
  dc1_private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  dc1_public_subnet_cidrs  = ["10.0.3.0/24", "10.0.4.0/24"]

  dc2_private_subnet_cidrs = ["10.0.5.0/24", "10.0.6.0/24"]
  dc2_public_subnet_cidrs  = ["10.0.7.0/24", "10.0.8.0/24"]
}

data "aws_availability_zones" "available" {
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
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = concat(local.dc1_private_subnet_cidrs, local.dc2_private_subnet_cidrs)
  public_subnets       = concat(local.dc1_public_subnet_cidrs, local.dc2_public_subnet_cidrs)
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
}
