# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "hcp_public_endpoint" {
  value = hcp_consul_cluster.this.consul_public_endpoint_url
}

output "token" {
  value     = hcp_consul_cluster.this.consul_root_token_secret_id
  sensitive = true
}

output "client" {
  value = {
    name            = "example_client_${local.client_suffix}"
    partition       = var.client_partition
    namespace       = var.client_namespace
    region          = var.region
    ecs_cluster_arn = aws_ecs_cluster.cluster_1.arn
  }
}

output "server" {
  value = {
    name            = "example_server_${local.server_suffix}"
    partition       = var.server_partition
    namespace       = var.server_namespace
    region          = var.region
    ecs_cluster_arn = aws_ecs_cluster.cluster_2.arn
  }
}
