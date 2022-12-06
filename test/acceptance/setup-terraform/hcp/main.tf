resource "hcp_hvn" "server" {
  hvn_id         = "hvn-${var.suffix}"
  cloud_provider = "aws"
  region         = var.region
  cidr_block     = "172.25.16.0/20"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "selected" {
  id = var.vpc.vpc_id
}

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
  destination_cidr = data.aws_vpc.selected.cidr_block
  target_link      = hcp_aws_network_peering.this.self_link
}

resource "aws_route" "peering" {
  count                     = length([var.vpc.public_route_table_ids[0], var.vpc.private_route_table_ids[0]])
  route_table_id            = [var.vpc.public_route_table_ids[0], var.vpc.private_route_table_ids[0]][count.index]
  destination_cidr_block    = hcp_hvn.server.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.peer.vpc_peering_connection_id
}

resource "hcp_consul_cluster" "this" {
  cluster_id         = "server-${var.suffix}"
  datacenter         = "dc1"
  hvn_id             = hcp_hvn.server.hvn_id
  tier               = "development"
  public_endpoint    = true
  min_consul_version = var.consul_version
}

resource "aws_secretsmanager_secret" "bootstrap_token" {
  name                    = "${var.suffix}-bootstrap-token"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "bootstrap_token" {
  secret_id     = aws_secretsmanager_secret.bootstrap_token.id
  secret_string = hcp_consul_cluster.this.consul_root_token_secret_id
}

resource "aws_secretsmanager_secret" "gossip_key" {
  name                    = "${var.suffix}-gossip-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "gossip_key" {
  secret_id     = aws_secretsmanager_secret.gossip_key.id
  secret_string = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["encrypt"]
}

resource "aws_secretsmanager_secret" "consul_ca_cert" {
  name                    = "${var.suffix}-consul-ca-cert"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "consul_ca_cert" {
  secret_id     = aws_secretsmanager_secret.consul_ca_cert.id
  secret_string = base64decode(hcp_consul_cluster.this.consul_ca_file)
}
