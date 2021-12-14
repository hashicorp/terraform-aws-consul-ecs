locals {
  # The goal here is to prune unused fields from the config.
  # This helps reduce the size of the CONSUL_ECS_CONFIG_JSON variable,
  # and keeps the JSON Schema in consul-ecs simple (no nullable fields).
  #
  # We use loops to prune null or empty fields (null, "", {}, or []).
  # A bit of magic here is this loop filter:
  #
  #   try(length(v) != 0, true)
  #
  # This returns the result of first expression that does not error, so we can
  # safely test for empty values without knowing their type.

  # TODO: Switch var.upstreams to camelCase so we don't need case conversion.
  camelCaseUpstreams = [for upstream in var.upstreams :
    {
      destinationName = upstream.destination_name
      localBindPort   = upstream.local_bind_port
    }
  ]

  meshServiceConfig = {
    name   = local.service_name
    port   = var.port
    tags   = var.consul_service_tags
    meta   = var.consul_service_meta
    checks = var.checks
  }

  meshConfig = {
    service = {
      for k, v in local.meshServiceConfig :
      k => v if v != null && try(length(v) != 0, true)
    }
    proxy = {
      upstreams = [
        for upstream in local.camelCaseUpstreams :
        { for k, v in upstream : k => v if v != null && try(length(v) != 0, true) }
      ]
    }
    healthSyncContainers = local.defaulted_check_containers
    bootstrapDir         = local.consul_data_mount.containerPath
  }

  config = {
    aclTokenSecret = {
      provider = "secrets-manager"
      configuration = {
        prefix                     = var.acl_secret_name_prefix
        consulClientTokenSecretArn = var.consul_client_token_secret_arn
      }
    }
    mesh = {
      for k, v in local.meshConfig :
      k => v if v != null && try(length(v) != 0, true)
    }
  }

  encoded_config = jsonencode(local.config)
}
