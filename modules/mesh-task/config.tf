locals {
  // Define the Consul ECS config file contents.
  serviceExtra = lookup(var.consul_ecs_config, "service", {})
  proxyExtra   = lookup(var.consul_ecs_config, "proxy", {})

  config = {
    service = merge(
      {
        name      = local.service_name
        tags      = var.consul_service_tags
        port      = var.port
        meta      = var.consul_service_meta
        checks    = var.checks
        namespace = var.consul_namespace
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
