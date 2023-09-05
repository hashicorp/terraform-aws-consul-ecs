# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "name" {
  value = local.example_server_app_name
}

output "consul_service_name" {
  value = "${var.name}-example-server-app"
}