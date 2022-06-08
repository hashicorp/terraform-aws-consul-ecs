locals {
  consulLogin = var.acls ? {
    enabled = var.acls
    method  = var.service_token_auth_method_name
    // TODO: Move this to a top-level partition field in the CONSUL_ECS_CONFIG_JSON
    extraLoginFlags = var.consul_partition != "" ? ["-partition", var.consul_partition] : []
  } : null

  // if mesh gateway WAN federation is enabled add the metadata to the gateway service registration that exposes the Consul servers.
  consul_service_meta = merge(
    var.consul_service_meta,
    var.enable_mesh_gateway_wan_federation ? { "consul-wan-federation" : "1" } : {}
  )

  config = {
    consulHTTPAddr   = var.consul_http_addr
    consulCACertFile = var.consul_https_ca_cert_arn != "" ? "/consul/consul-https-ca-cert.pem" : ""
    consulLogin      = local.consulLogin
    gateway = {
      kind      = var.kind
      name      = local.service_name
      tags      = var.consul_service_tags
      meta      = local.consul_service_meta
      namespace = var.consul_namespace
      partition = var.consul_partition
      lanAddress = {
        address = var.lan_address
        port    = var.lan_port
      }
      wanAddress = {
        address = var.wan_address
        port    = var.wan_port
      }
    }
    healthSyncContainers = []
    bootstrapDir         = local.consul_data_mount.containerPath
  }

  encoded_config = jsonencode(local.config)
}
