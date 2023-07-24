# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  // Define the Consul ECS config file contents.
  serviceExtra = lookup(var.consul_ecs_config, "service", {})
  proxyExtra   = lookup(var.consul_ecs_config, "proxy", {})
  loginExtra   = lookup(var.consul_ecs_config, "consulLogin", {})

  consulLogin = var.acls ? {
    enabled = var.acls
    method  = var.service_token_auth_method_name
  } : null

  httpTLSSettings = merge(
    {
      port = var.tls ? 8501 : 8500
      https = var.tls
    },
    var.http_tls_config
  )

  grpcTLSSettings = merge(
    {
      port = var.tls ? 8503 : 8502
    },
    var.grpc_tls_config
  )

  config = {
    consulLogin = merge(local.consulLogin, local.loginExtra)
    service = merge(
      {
        name      = local.service_name
        tags      = var.consul_service_tags
        port      = var.port
        meta      = var.consul_service_meta
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
      hosts           = var.consul_server_address
      skipServerWatch = var.skip_server_watch
      defaults = {
        tls           = var.tls
        tlsServerName = var.tls_server_name
        caCertFile    = var.ca_cert_file
      }
      http = local.httpTLSSettings
      grpc = local.grpcTLSSettings
    }
  }

  encoded_config = jsonencode(local.config)
}