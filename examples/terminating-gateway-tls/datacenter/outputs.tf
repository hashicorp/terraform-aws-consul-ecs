# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

output "dev_consul_server" {
  value = module.dev_consul_server
}

output "datacenter" {
  value = var.datacenter
}

output "private_subnets" {
  value = var.private_subnets
}

output "public_subnets" {
  value = var.public_subnets
}
