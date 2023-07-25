# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  httpTLSSettings = merge(
    {
      port  = var.tls ? 8501 : 8500
      https = var.tls
    },
    var.http_config
  )

  grpcTLSSettings = merge(
    {
      port = var.tls ? 8503 : 8502
    },
    var.grpc_config
  )

  config = {
    controller = {
      iamRolePath       = var.iam_role_path
      partitionsEnabled = var.consul_partitions_enabled
      partition         = var.consul_partitions_enabled ? var.consul_partition : ""
    }
    bootstrapDir = "/consul"
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