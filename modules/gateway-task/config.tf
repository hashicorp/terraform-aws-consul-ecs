# Copyright IBM Corp. 2021, 2026
# SPDX-License-Identifier: MPL-2.0

locals {
  loginExtra  = lookup(var.consul_ecs_config, "consulLogin", {})
  tProxyExtra = lookup(var.consul_ecs_config, "transparentProxy", {})

  consulLogin = var.acls ? {
    enabled = var.acls
    method  = var.service_token_auth_method_name
  } : null

  // The namespace for gateways is always "default" for enterprise or "" for OSS.
  consul_namespace = var.consul_partition != "" ? "default" : ""

  // If mesh gateway WAN federation is enabled add the metadata to the gateway service registration that exposes the Consul servers.

  // Version keys ('ecs-version', 'dataplane-version') are reserved and always reflect the image version variables
  // and cannot be overridden via var.consul_service_meta.
  // Please use var.consul_ecs_image_version and var.consul_dataplane_image_version to set them.
  // Keys with a 'consul-' prefix are only valid if that key is recognised by Consul; unrecognised 'consul-' keys cause service registration to fail. Refer: https://github.com/hashicorp/consul/blob/9a38fac228fae7960f12f5b2a45c7548c90e8224/agent/structs/structs.go#L182.
  consul_service_meta = merge(
    var.consul_service_meta,
    var.enable_mesh_gateway_wan_federation ? { "consul-wan-federation" : "1" } : {},
    {
      "ecs-version"       = var.consul_ecs_image_version
      "dataplane-version" = var.consul_dataplane_image_version
    }
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

  transparentProxy = {
    enabled              = var.enable_transparent_proxy
    excludeInboundPorts  = var.exclude_inbound_ports
    excludeOutboundPorts = var.exclude_outbound_ports
    excludeOutboundCIDRs = var.exclude_outbound_cidrs
    excludeUIDs          = var.exclude_uids
    consulDNS = {
      enabled = var.enable_consul_dns
    }
  }

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
    transparentProxy = merge(local.tProxyExtra, local.transparentProxy)
  }

  encoded_config = jsonencode(local.config)
}
