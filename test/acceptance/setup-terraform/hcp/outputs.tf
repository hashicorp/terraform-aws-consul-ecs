# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

output "consul_public_endpoint_url" {
  value = hcp_consul_cluster.this.consul_public_endpoint_url
}

output "consul_private_endpoint_url" {
  value = hcp_consul_cluster.this.consul_private_endpoint_url
}

output "token" {
  value     = hcp_consul_cluster.this.consul_root_token_secret_id
  sensitive = true
}

output "retry_join" {
  value = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["retry_join"]
}

output "bootstrap_token_secret_arn" {
  value = aws_secretsmanager_secret.bootstrap_token.arn
}

output "gossip_key_secret_arn" {
  value = aws_secretsmanager_secret.gossip_key.arn
}

output "consul_ca_cert_secret_arn" {
  value = aws_secretsmanager_secret.consul_ca_cert.arn
}
