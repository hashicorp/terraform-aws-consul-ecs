output "hcp_public_endpoint" {
  value = hcp_consul_cluster.this.consul_public_endpoint_url
}

output "token" {
  value     = hcp_consul_cluster.this.consul_root_token_secret_id
  sensitive = true
}