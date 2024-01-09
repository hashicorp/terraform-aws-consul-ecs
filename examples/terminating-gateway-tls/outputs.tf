# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "consul_server_lb_address" {
  value = "http://${module.dc1.dev_consul_server.lb_dns_name}:8500"
}

output "consul_server_bootstrap_token" {
  value = module.dc1.dev_consul_server.bootstrap_token_id
}

output "mesh_client_lb_address" {
  value = "http://${aws_lb.example_client_app.dns_name}:9090/ui"
}

output "certs_efs_file_system_address" {
  value = aws_efs_file_system.certs_efs.id
}

output "non_mesh_server_lb_dns_name" {
  value = aws_lb.example_server_app.dns_name
}