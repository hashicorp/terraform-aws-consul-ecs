# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "wan_address" {
  value = module.mesh_gateway.wan_address
}

output "wan_port" {
  value = module.mesh_gateway.wan_port
}
