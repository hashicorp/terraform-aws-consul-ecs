# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  loginExtra = lookup(var.consul_ecs_config, "consulLogin", {})

  consulLogin = var.acls ? {
    enabled = var.acls
    method  = var.service_token_auth_method_name
  } : null

  // The namespace for gateways is always "default" for enterprise or "" for OSS.
  consul_namespace = var.consul_partition != "" ? "default" : ""

  // if mesh gateway WAN federation is enabled add the metadata to the gateway service registration that exposes the Consul servers.
  consul_service_meta = merge(
    var.consul_service_meta,
    var.enable_mesh_gateway_wan_federation ? { "consul-wan-federation" : "1" } : {}
  )

  config = {
    consulLogin      = merge(local.consulLogin, local.loginExtra)
    gateway = {
      kind      = var.kind
      name      = local.service_name
      tags      = var.consul_service_tags
      meta      = local.consul_service_meta
      namespace = local.consul_namespace
      partition = var.consul_partition
      lanAddress = {
        address = var.lan_address
        port    = local.lan_port
      }
      wanAddress = {
        address = local.wan_address
        port    = local.wan_port
      }
    }
    healthSyncContainers = []
    bootstrapDir         = local.consul_data_mount.containerPath
    consulServers = {
      hosts = var.consul_server_addr
      defaults = {
        tls = true
      }
      http = {
        port = 8501
        https = true
      }
      grpc = {
        port = 8503
      }
    }
  }

  encoded_config = jsonencode(local.config)
}
