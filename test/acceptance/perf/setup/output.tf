# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "consul_elb_url" {
  value = "http://${module.dev_consul_server.lb_dns_name}:8500"
}

output "bootstrap_token" {
  value     = module.dev_consul_server.bootstrap_token_id
  sensitive = true
}