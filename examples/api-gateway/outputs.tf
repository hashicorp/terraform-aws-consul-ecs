# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

output "consul_server_lb_address" {
  value = "http://${module.dc1.dev_consul_server.lb_dns_name}:8500"
}

output "consul_server_bootstrap_token" {
  value     = module.dc1.dev_consul_server.bootstrap_token_id
  sensitive = true
}

output "api_gateway_lb_url" {
  value = "http://${aws_lb.this.dns_name}:8443"
}