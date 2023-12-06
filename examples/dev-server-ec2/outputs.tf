# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "consul_server_lb_address" {
  value = "http://${module.dev_consul_server.lb_dns_name}:8500"
}

output "mesh_client_lb_address" {
  value = "http://${aws_lb.example_client_app.dns_name}:9090/ui"
}

output "bastion_ip" {
  value = var.public_ssh_key != null ? module.bastion[0].ip : null
}

output "client_app_consul_service_name" {
  value = "${var.name}-example-client-app"
}

output "server_app_consul_service_name" {
  value = "${var.name}-example-server-app"
}