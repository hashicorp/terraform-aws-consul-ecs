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

  httpSettings = merge(
    {
      port  = var.tls ? 8501 : 8500
      https = var.tls
    },
    var.http_config
  )

  grpcSettings = merge(
    {
      port = var.tls ? 8503 : 8502
    },
    var.grpc_config
  )

  config = {
    consulLogin = merge(local.consulLogin, local.loginExtra)
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
      hosts           = var.consul_server_hosts
      skipServerWatch = var.skip_server_watch
      defaults = {
        tls           = var.tls
        tlsServerName = var.tls_server_name
      }
      http = local.httpSettings
      grpc = local.grpcSettings
    }
  }

  encoded_config = jsonencode(local.config)
}
