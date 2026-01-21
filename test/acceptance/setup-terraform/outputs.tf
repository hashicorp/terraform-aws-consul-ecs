# Copyright (c) HashiCorp, Inc.
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

output "consul_version" {
  value = var.consul_version
}
