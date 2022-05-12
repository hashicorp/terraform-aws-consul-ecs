locals {
  // Define the Consul ECS config file contents.
  serviceExtra = lookup(var.consul_ecs_config, "service", {})
  proxyExtra   = lookup(var.consul_ecs_config, "proxy", {})

  consulLogin = var.acls ? {
    enabled = var.acls
    method  = var.service_token_auth_method_name
    // TODO: Move this to a top-level partition field in the CONSUL_ECS_CONFIG_JSON
    extraLoginFlags = var.consul_partition != "" ? ["-partition", var.consul_partition] : []
  } : null

  config = {
    consulHTTPAddr   = var.consul_http_addr
    consulCACertFile = var.consul_https_ca_cert_arn != "" ? "/consul/consul-https-ca-cert.pem" : ""
    consulLogin      = local.consulLogin
    service = merge(
      {
        name      = local.service_name
        tags      = var.consul_service_tags
        port      = var.port
        meta      = var.consul_service_meta
        checks    = var.checks
        namespace = var.consul_namespace
        partition = var.consul_partition
      },
      local.serviceExtra
    )
    proxy = merge(
      {
        upstreams = var.upstreams
      },
      local.proxyExtra
    )
    healthSyncContainers = local.defaulted_check_containers
    bootstrapDir         = local.consul_data_mount.containerPath
  }

  encoded_config = jsonencode(local.config)
}
