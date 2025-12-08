# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

output "dc1_server_url" {
  value = "http://${module.dc1.dev_consul_server.lb_dns_name}:8500"
}

output "dc2_server_url" {
  value = "http://${module.dc2.dev_consul_server.lb_dns_name}:8500"
}

output "dc1_server_bootstrap_token" {
  value     = module.dc1.dev_consul_server.bootstrap_token_id
  sensitive = true
}

output "dc2_server_bootstrap_token" {
  value     = module.dc2.dev_consul_server.bootstrap_token_id
  sensitive = true
}

output "dc1_default_partition_apps" {
  value = {
    partition       = "default"
    namespace       = "default"
    region          = var.region
    ecs_cluster_arn = module.cluster1.ecs_cluster.arn
    client = {
      name                = module.client_app_dc1.name
      consul_service_name = module.client_app_dc1.consul_service_name
      port                = module.client_app_dc1.port
      lb_address          = "http://${module.client_app_dc1.lb_dns_name}:${module.client_app_dc1_part1.port}/ui"
      lb_dns_name         = module.client_app_dc1.lb_dns_name
    }
    server = {
      name                = module.server_app_dc1.name
      consul_service_name = module.server_app_dc1.consul_service_name
    }
  }
}

output "dc1_part1_partition_apps" {
  value = {
    partition       = var.dc1_consul_admin_partition
    namespace       = "default"
    region          = var.region
    ecs_cluster_arn = module.cluster2.ecs_cluster.arn
    client = {
      name                = module.client_app_dc1_part1.name
      consul_service_name = module.client_app_dc1_part1.consul_service_name
      port                = module.client_app_dc1_part1.port
      lb_address          = "http://${module.client_app_dc1_part1.lb_dns_name}:${module.client_app_dc1_part1.port}/ui"
      lb_dns_name         = module.client_app_dc1_part1.lb_dns_name
    }
    server = {
      name                = module.server_app_dc1_part1.name
      consul_service_name = module.server_app_dc1_part1.consul_service_name
    }
  }
}

output "dc2_default_partition_apps" {
  value = {
    partition       = "default"
    namespace       = "default"
    region          = var.region
    ecs_cluster_arn = module.cluster3.ecs_cluster.arn
    client = {
      name                = module.client_app_dc2.name
      consul_service_name = module.client_app_dc2.consul_service_name
      port                = module.client_app_dc2.port
      lb_address          = "http://${module.client_app_dc2.lb_dns_name}:${module.client_app_dc2.port}/ui"
      lb_dns_name         = module.client_app_dc2.lb_dns_name
    }
    server = {
      name                = module.server_app_dc2.name
      consul_service_name = module.server_app_dc2.consul_service_name
    }
  }
}