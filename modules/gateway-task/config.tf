locals {
  consulLogin = var.acls ? {
    enabled = var.acls
    method  = var.service_token_auth_method_name
    // TODO: Move this to a top-level partition field in the CONSUL_ECS_CONFIG_JSON
    extraLoginFlags = var.consul_partition != "" ? ["-partition", var.consul_partition] : []
  } : null

  consul_service_meta = var.consul_service_meta

  // if mesh gateway WAN federation is enabled add the metadata to the gateway service registration that exposes the Consul servers.
  consul_gateway_meta = var.enable_mesh_gateway_wan_federation ? { "consul-wan-federation" : "1" } : {}

  config = {
    consulHTTPAddr   = var.consul_http_addr
    consulCACertFile = var.consul_https_ca_cert_arn != "" ? "/consul/consul-https-ca-cert.pem" : ""
    consulLogin      = local.consulLogin
    service = {
      name      = local.service_name
      tags      = var.consul_service_tags
      port      = 0 // note: field is required by consul-ecs schema. Not used for gateway.
      meta      = local.consul_service_meta
      namespace = var.consul_namespace
      partition = var.consul_partition
    }
    gateway = {
      kind = var.kind
      lanAddress = {
        address = var.lan_address
        port    = var.lan_port
      }
      wanAddress = {
        address = var.wan_address
        port    = var.wan_port
      }
      meta = local.consul_gateway_meta
    }
    healthSyncContainers = []
    bootstrapDir         = local.consul_data_mount.containerPath
  }

  encoded_config = jsonencode(local.config)
}
