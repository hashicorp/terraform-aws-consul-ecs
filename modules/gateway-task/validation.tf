# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  require_tls_for_wan_federation             = !var.enable_mesh_gateway_wan_federation || var.tls ? null : assert(false, "tls must be true when enable_mesh_gateway_wan_federation is true")
  wan_address_xor_lb_enabled                 = !(var.wan_address != "" && var.lb_enabled) ? null : assert(false, "Only one of wan_address or lb_enabled may be provided")
  require_lb_subnets_for_lb                  = !(var.lb_enabled && length(var.lb_subnets) < 1) ? null : assert(false, "lb_subnets is required when lb_enabled is true")
  require_lb_vpc_for_lb                      = !(var.lb_enabled && var.lb_vpc_id == "") ? null : assert(false, "lb_vpc_id is required when lb_enabled is true")
  create_xor_modify_security_group           = !(var.lb_create_security_group && var.lb_modify_security_group) ? null : assert(false, "Only one of lb_create_security_group or lb_modify_security_group may be true")
  require_sg_id_for_modify                   = !(var.lb_modify_security_group && var.lb_modify_security_group_id == "") ? null : assert(false, "lb_modify_security_group_id is required when lb_modify_security_group is true")
  custom_lb_config_check                     = !(var.lb_enabled && length(var.custom_load_balancer_config) > 0) ? null : assert(false, "custom_load_balancer_config must only be supplied when var.lb_enabled is false")
  require_ec2_compability_for_tproxy_support = !(var.enable_transparent_proxy && (length(var.requires_compatibilities) != 1 || var.requires_compatibilities[0] != "EC2")) ? null : assert(false, "transparent proxy is supported only in ECS EC2 mode.")
  require_tproxy_enabled_for_consul_dns      = !(var.enable_consul_dns && !var.enable_transparent_proxy) ? null : assert(false, "var.enable_transparent_proxy must be set to true for Consul DNS to be enabled.")
}
