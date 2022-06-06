output "ecs_cluster" {
  value = aws_ecs_cluster.this
}

output "bootstrap_token_id" {
  value = hcp_consul_cluster.this.consul_root_token_secret_id
}

output "bootstrap_token_secret_arn" {
  value = aws_secretsmanager_secret.bootstrap_token.arn
}

output "gossip_key_secret_arn" {
  value = aws_secretsmanager_secret.gossip_key.arn
}

output "ca_cert_secret_arn" {
  value = aws_secretsmanager_secret.consul_ca_cert.arn
}

output "hvn_id" {
  value = hcp_hvn.server.hvn_id
}

output "consul_public_endpoint_url" {
  value = hcp_consul_cluster.this.consul_public_endpoint_url
}

output "consul_private_endpoint_url" {
  value = hcp_consul_cluster.this.consul_private_endpoint_url
}

output "hcp_consul_self_link" {
  value = hcp_consul_cluster.this.self_link
}

output "log_group" {
  value = aws_cloudwatch_log_group.log_group
}

output "retry_join" {
  value = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["retry_join"]
}

output "datacenter" {
  value = var.datacenter
}

output "private_subnets" {
  value = var.vpc.private_subnets
}

output "public_subnets" {
  value = var.vpc.public_subnets
}
