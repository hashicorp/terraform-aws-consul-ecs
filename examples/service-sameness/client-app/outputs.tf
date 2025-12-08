# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

output "lb_dns_name" {
  value = aws_lb.example_client_app.dns_name
}

output "name" {
  value = local.example_client_app_name
}

output "consul_service_name" {
  value = "${var.name}-example-client-app"
}

output "port" {
  value = var.port
}