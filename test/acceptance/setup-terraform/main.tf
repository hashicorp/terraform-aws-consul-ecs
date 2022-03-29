provider "aws" {
  region = var.region
}

locals {
  name   = "consul-ecs-${random_string.suffix.result}"
  suffix = random_string.suffix.result
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
  version = "2.78.0"

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
resource "aws_ecs_cluster" "cluster_1" {
  name = "${local.name}-1"
  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "ecs_ccp_1" {
  cluster_name       = aws_ecs_cluster.cluster_1.name
  capacity_providers = [var.launch_type]

  default_capacity_provider_strategy {
    capacity_provider = var.launch_type
  }
}

resource "aws_ecs_cluster" "cluster_2" {
  name = "${local.name}-2"
  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "ecs_ccp_2" {
  cluster_name       = aws_ecs_cluster.cluster_2.name
  capacity_providers = [var.launch_type]

  default_capacity_provider_strategy {
    capacity_provider = var.launch_type
  }
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = local.name
  tags = var.tags
}

// Policy that allows execution of remote commands in ECS tasks.
resource "aws_iam_policy" "execute_command" {
  name   = "ecs-execute-command-${local.suffix}"
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

}

resource "hcp_hvn" "server" {
  hvn_id         = "hvn-${local.suffix}"
  cloud_provider = "aws"
  region         = var.region
  cidr_block     = "172.25.16.0/20"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "selected" {
  id = module.vpc.vpc_id
}

resource "hcp_aws_network_peering" "this" {
  peering_id      = "${hcp_hvn.server.hvn_id}-peering"
  hvn_id          = hcp_hvn.server.hvn_id
  peer_vpc_id     = module.vpc.vpc_id
  peer_account_id = data.aws_caller_identity.current.account_id
  peer_vpc_region = var.region
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  vpc_peering_connection_id = hcp_aws_network_peering.this.provider_peering_id
  auto_accept               = true
}

resource "hcp_hvn_route" "peering_route" {
  depends_on       = [aws_vpc_peering_connection_accepter.peer]
  hvn_link         = hcp_hvn.server.self_link
  hvn_route_id     = "${hcp_hvn.server.hvn_id}-peering-route"
  destination_cidr = data.aws_vpc.selected.cidr_block
  target_link      = hcp_aws_network_peering.this.self_link
}

resource "aws_route" "peering" {
  count                     = length([module.vpc.public_route_table_ids[0], module.vpc.private_route_table_ids[0]])
  route_table_id            = [module.vpc.public_route_table_ids[0], module.vpc.private_route_table_ids[0]][count.index]
  destination_cidr_block    = hcp_hvn.server.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.peer.vpc_peering_connection_id
}

resource "hcp_consul_cluster" "this" {
  cluster_id      = "server-${local.suffix}"
  datacenter      = "dc1"
  hvn_id          = hcp_hvn.server.hvn_id
  tier            = "development"
  public_endpoint = true
}

resource "aws_secretsmanager_secret" "bootstrap_token" {
  name = "${local.suffix}-bootstrap-token"
}

resource "aws_secretsmanager_secret_version" "bootstrap_token" {
  secret_id     = aws_secretsmanager_secret.bootstrap_token.id
  secret_string = hcp_consul_cluster.this.consul_root_token_secret_id
}

resource "aws_secretsmanager_secret" "gossip_key" {
  name = "${local.suffix}-gossip-key"
}

resource "aws_secretsmanager_secret_version" "gossip_key" {
  secret_id     = aws_secretsmanager_secret.gossip_key.id
  secret_string = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["encrypt"]
}

resource "aws_secretsmanager_secret" "consul_ca_cert" {
  name = "${local.suffix}-consul-ca-cert"
}

resource "aws_secretsmanager_secret_version" "consul_ca_cert" {
  secret_id     = aws_secretsmanager_secret.consul_ca_cert.id
  secret_string = base64decode(hcp_consul_cluster.this.consul_ca_file)
}
