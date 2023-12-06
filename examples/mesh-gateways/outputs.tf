# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "bootstrap_token" {
  value     = module.dc1.dev_consul_server.bootstrap_token_id
  sensitive = true
}

output "client_lb_address" {
  value = "http://${aws_lb.example_client_app.dns_name}:9090/ui"
}

output "dc1_server_url" {
  value = "http://${module.dc1.dev_consul_server.lb_dns_name}:8500"
}

output "dc2_server_url" {
  value = "http://${module.dc2.dev_consul_server.lb_dns_name}:8500"
}

output "client_app_consul_service_name" {
  value = local.example_client_app_name
}

output "server_app_consul_service_name" {
  value = local.example_server_app_name
}

output "dc1_mesh_gateway_name" {
  value = local.mgw_name_1
}

output "dc2_mesh_gateway_name" {
  value = local.mgw_name_2
}