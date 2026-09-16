# Copyright IBM Corp. 2021, 2026
# SPDX-License-Identifier: MPL-2.0

locals {
  // Define the Consul ECS config file contents.
  serviceExtra = lookup(var.consul_ecs_config, "service", {})

  // Version keys ('ecs-version', 'dataplane-version') are reserved and always reflect the image version variables
  // and cannot be overridden via var.consul_service_meta.
  // Please use var.consul_ecs_image_version and var.consul_dataplane_image_version to set them.
  // Keys with a 'consul-' prefix are only valid if that key is recognised by Consul; unrecognised 'consul-' keys cause service registration to fail. Refer: https://github.com/hashicorp/consul/blob/9a38fac228fae7960f12f5b2a45c7548c90e8224/agent/structs/structs.go#L182.
  service_meta = merge(
    var.consul_service_meta,
    {
      "ecs-version"       = var.consul_ecs_image_version
      "dataplane-version" = var.consul_dataplane_image_version
    }
  )
  proxyExtra  = lookup(var.consul_ecs_config, "proxy", {})
  loginExtra  = lookup(var.consul_ecs_config, "consulLogin", {})
  tProxyExtra = lookup(var.consul_ecs_config, "transparentProxy", {})

  consulLogin = var.acls ? {
    enabled = var.acls
    method  = var.service_token_auth_method_name
  } : null

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
    service = merge(
      {
        name      = local.service_name
        tags      = var.consul_service_tags
        port      = var.port
        meta      = local.service_meta
        namespace = var.consul_namespace
        partition = var.consul_partition
      },
      local.serviceExtra
    )
    proxy = merge(
      {
        publicListenerPort = var.envoy_public_listener_port
        upstreams          = var.upstreams
        healthCheckPort    = var.envoy_readiness_port
      },
      local.proxyExtra
    )
    healthSyncContainers = local.defaulted_check_containers
    bootstrapDir         = local.consul_data_mount.containerPath
    consulServers = {
      hosts           = var.consul_server_hosts
      skipServerWatch = var.skip_server_watch
      defaults = {
        tls           = var.tls
        tlsServerName = var.tls_server_name
        caCertFile    = var.ca_cert_file
      }
      http = local.httpSettings
      grpc = local.grpcSettings
    }
    transparentProxy = merge(local.tProxyExtra, local.transparentProxy)
  }

  encoded_config = jsonencode(local.config)
}