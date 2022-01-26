locals {
  // Define the Consul ECS config file contents.
  serviceExtra = lookup(var.consul_ecs_config, "service", {})


  config = {
    service = merge(
      {
        name      = local.service_name
        tags      = var.consul_service_tags
        port      = 0 // note: field is required by consul-ecs schema. Not used for gateway.
        meta      = var.consul_service_meta
        namespace = var.consul_namespace
        partition = var.consul_partition
      },
      local.serviceExtra
    )
    proxy = {
      config = lookup(var.consul_ecs_config, "config",
        lookup(var.consul_ecs_config, "proxy", {})
      )
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
    }
    healthSyncContainers = []
    bootstrapDir         = local.consul_data_mount.containerPath
  }

  encoded_config = jsonencode(local.config)
}
