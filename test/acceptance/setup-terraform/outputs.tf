output "ecs_cluster_arn" {
  value = aws_ecs_cluster.cluster_1.arn
}

output "ecs_cluster_1_arn" {
  value = aws_ecs_cluster.cluster_1.arn
}

output "ecs_cluster_2_arn" {
  value = aws_ecs_cluster.cluster_2.arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "launch_type" {
  value = var.launch_type
}

output "subnets" {
  value = module.vpc.private_subnets
}

output "suffix" {
  value = random_string.suffix.result
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.log_group.name
}

output "region" {
  value = var.region
}

output "tags" {
  value = var.tags
}

output "route_table_ids" {
  value = [module.vpc.public_route_table_ids[0], module.vpc.private_route_table_ids[0]]
}

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
