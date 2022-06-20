locals {
  require_tls_for_wan_federation = var.enable_mesh_gateway_wan_federation && !var.tls ? file("ERROR: tls must be true when enable_mesh_gateway_wan_federation is true") : null
  wan_address_xor_lb_enabled     = var.wan_address != "" && var.lb_enabled ? file("ERROR: Only one of wan_address or lb_enabled may be provided") : null
  require_lb_subnets_for_lb      = var.lb_enabled && length(var.lb_subnets) < 1 ? file("ERROR: lb_subnets is required when lb_enabled is true") : null
  require_lb_vpc_for_lb          = var.lb_enabled && var.lb_vpc_id == "" ? file("ERROR: lb_vpc_id is required when lb_enabled is true") : null

  create_xor_modify_security_group = var.lb_create_security_group && var.lb_modify_security_group ? file("ERROR: Only one of lb_create_security_group or lb_modify_security_group may be true") : null
  require_sg_id_for_modify         = var.lb_modify_security_group && var.lb_modify_security_group_id == "" ? file("ERROR: lb_modify_security_group_id is required when lb_modify_security_group is true") : null
}
