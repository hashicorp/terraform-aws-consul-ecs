locals {
  retry_join_wan_xor_primary_gateways = length(var.retry_join_wan) > 0 && var.enable_mesh_gateway_wan_federation ? file("ERROR: Only one of retry_join_wan or enable_mesh_gateway_wan_federation may be provided.") : null
}
