// Create HCP Consul resources.
resource "hcp_hvn" "server" {
  hvn_id         = var.name
  cloud_provider = "aws"
  region         = var.region
  cidr_block     = var.hvn_cidr_block
}

data "aws_caller_identity" "current" {}

resource "hcp_aws_network_peering" "this" {
  peering_id      = "${hcp_hvn.server.hvn_id}-peering"
  hvn_id          = hcp_hvn.server.hvn_id
  peer_vpc_id     = var.vpc.vpc_id
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
  destination_cidr = var.vpc.vpc_cidr_block
  target_link      = hcp_aws_network_peering.this.self_link
}

resource "aws_route" "peering" {
  count                     = length([var.vpc.public_route_table_ids[0], var.vpc.private_route_table_ids[0]])
  route_table_id            = [var.vpc.public_route_table_ids[0], var.vpc.private_route_table_ids[0]][count.index]
  destination_cidr_block    = hcp_hvn.server.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.peer.vpc_peering_connection_id
}

resource "hcp_consul_cluster" "this" {
  cluster_id         = var.name
  datacenter         = var.datacenter
  hvn_id             = hcp_hvn.server.hvn_id
  tier               = "development"
  public_endpoint    = true
  min_consul_version = "1.12.0"

  primary_link            = var.is_secondary ? var.hcp_primary_link : ""
  auto_hvn_to_hvn_peering = var.is_secondary
}


// Create AWS Secrets Manager secrets required by the mesh-tasks and ACL controllers
resource "aws_secretsmanager_secret" "bootstrap_token" {
  name                    = "${var.name}-bootstrap-token"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "bootstrap_token" {
  secret_id     = aws_secretsmanager_secret.bootstrap_token.id
  secret_string = hcp_consul_cluster.this.consul_root_token_secret_id
}

resource "aws_secretsmanager_secret" "gossip_key" {
  name                    = "${var.name}-gossip-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "gossip_key" {
  secret_id     = aws_secretsmanager_secret.gossip_key.id
  secret_string = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["encrypt"]
}

resource "aws_secretsmanager_secret" "consul_ca_cert" {
  name                    = "${var.name}-consul-ca-cert"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "consul_ca_cert" {
  secret_id     = aws_secretsmanager_secret.consul_ca_cert.id
  secret_string = base64decode(hcp_consul_cluster.this.consul_ca_file)
}
