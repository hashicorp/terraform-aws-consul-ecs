# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

output "ecs_cluster_arns" {
  value = [for c in aws_ecs_cluster.clusters : c.arn]
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "launch_type" {
  value = var.launch_type
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "public_subnets" {
  value = module.vpc.public_subnets
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

output "enable_hcp" {
  value = var.enable_hcp
}

output "consul_public_endpoint_url" {
  value = var.enable_hcp ? module.hcp[0].consul_public_endpoint_url : ""
}

output "consul_private_endpoint_url" {
  value = var.enable_hcp ? module.hcp[0].consul_private_endpoint_url : ""
}

output "token" {
  value     = var.enable_hcp ? module.hcp[0].token : ""
  sensitive = true
}

output "retry_join" {
  value = var.enable_hcp ? module.hcp[0].retry_join : []
}

output "bootstrap_token_secret_arn" {
  value = var.enable_hcp ? module.hcp[0].bootstrap_token_secret_arn : ""
}

output "gossip_key_secret_arn" {
  value = var.enable_hcp ? module.hcp[0].gossip_key_secret_arn : ""
}

output "consul_ca_cert_secret_arn" {
  value = var.enable_hcp ? module.hcp[0].consul_ca_cert_secret_arn : ""
}

output "consul_version" {
  value = var.consul_version
}
