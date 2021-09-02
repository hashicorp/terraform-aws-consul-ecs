resource "hcp_consul_cluster" "example" {
  cluster_id      = "dc1"
  hvn_id          = hcp_hvn.server.hvn_id
  tier            = "development"
  public_endpoint = true
}

resource "aws_secretsmanager_secret" "bootstrap_token" {
  name = "${var.name}-bootstrap-token"
}

resource "aws_secretsmanager_secret_version" "bootstrap_token" {
  secret_id     = aws_secretsmanager_secret.bootstrap_token.id
  secret_string = hcp_consul_cluster.example.consul_root_token_secret_id
}

resource "aws_secretsmanager_secret" "gossip_key" {
  name = "${var.name}-gossip-key"
}

resource "aws_secretsmanager_secret_version" "gossip_key" {
  secret_id     = aws_secretsmanager_secret.gossip_key.id
  secret_string = jsondecode(base64decode(hcp_consul_cluster.example.consul_config_file))["encrypt"]
}

resource "aws_secretsmanager_secret" "consul_ca_cert" {
  name = "${var.name}-consul-ca-cert"
}

resource "aws_secretsmanager_secret_version" "consul_ca_cert" {
  secret_id     = aws_secretsmanager_secret.consul_ca_cert.id
  secret_string = base64decode(hcp_consul_cluster.example.consul_ca_file)
}