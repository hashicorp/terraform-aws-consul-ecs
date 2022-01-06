locals {
  // Define the Consul ECS config file contents.
  # TODO: Switch var.upstreams to camelCase so we don't need case conversion.
  camelCaseUpstreams = [for upstream in var.upstreams :
    {
      destinationName = upstream.destination_name
      localBindPort   = upstream.local_bind_port
    }
  ]

  config = {
    service = {
      name   = local.service_name
      port   = var.port
      tags   = var.consul_service_tags
      meta   = var.consul_service_meta
      checks = var.checks
    }
    proxy = {
      upstreams = local.camelCaseUpstreams
    }
    healthSyncContainers = local.defaulted_check_containers
    bootstrapDir         = local.consul_data_mount.containerPath
  }

  encoded_config = jsonencode(local.config)
}
