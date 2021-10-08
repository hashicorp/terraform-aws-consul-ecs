provider "aws" {
  region = var.region
}

# Find our public IP to restrict ingress in security groups.
# NOTE: This produces a warning because checkip.amazonaws.com does not return a Content-Type header.
data "http" "my_ip" {
  count = var.ingress_ip == "" ? 1 : 0
  url   = "https://checkip.amazonaws.com/"
}

locals {
  name       = "consul-ecs-${random_string.suffix.result}"
  ingress_ip = var.ingress_ip != "" ? var.ingress_ip : trimspace(data.http.my_ip[0].body)
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

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.78.0"

  name                 = local.name
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  tags                 = var.tags

  manage_default_security_group = true
  default_security_group_ingress = [
    {
      protocol    = "-1"
      from_port   = "0"
      to_port     = "0"
      cidr_blocks = "${local.ingress_ip}/32" # Comma-separated string
    },
    {
      protocol  = "-1"
      self      = "true"
      from_port = "0"
      to_port   = "0"
    }
  ]
  default_security_group_egress = [{
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = "0.0.0.0/0"
  }]
}

resource "aws_ecs_cluster" "this" {
  name               = local.name
  capacity_providers = var.launch_type == "FARGATE" ? ["FARGATE"] : null
  tags               = var.tags
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = local.name
  tags = var.tags
}

resource "aws_lb" "this" {
  name               = local.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.vpc.default_security_group_id]
  subnets            = module.vpc.public_subnets
}