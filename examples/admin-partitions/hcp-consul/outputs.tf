output "hcp_public_endpoint" {
  value = hcp_consul_cluster.this.consul_public_endpoint_url
}

output "hcp_private_endpoint" {
  value = hcp_consul_cluster.this.consul_private_endpoint_url
}

output "token" {
  value     = hcp_consul_cluster.this.consul_root_token_secret_id
  sensitive = true
}

output "bootstrap_token_arn" {
  value = aws_secretsmanager_secret.bootstrap_token.arn
}

output "consul_ca_cert_arn" {
  value = aws_secretsmanager_secret.consul_ca_cert.arn
}

output "gossip_key_arn" {
  value = aws_secretsmanager_secret.gossip_key.arn
}

output "retry_join" {
  value = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["retry_join"]
}

output "suffix" {
  value = var.suffix
}