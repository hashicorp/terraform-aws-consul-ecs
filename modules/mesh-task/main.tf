data "aws_region" "current" {}

locals {
  // Must be updated for each release, and after each release to return to a "-dev" version.
  version_string = "0.4.1-dev"

  gossip_encryption_enabled = var.gossip_key_secret_arn != ""
  consul_data_volume_name   = "consul_data"
  consul_data_mount = {
    sourceVolume  = local.consul_data_volume_name
    containerPath = "/consul"
    readOnly      = true
  }
  consul_data_mount_read_write = merge(
    local.consul_data_mount,
    { readOnly = false },
  )

  consul_binary_volume_name = "consul_binary"

  // Optionally, users can override the application container's entrypoint.
  enable_app_entrypoint = var.application_shutdown_delay_seconds == null ? false : var.application_shutdown_delay_seconds > 0
  app_entrypoint = local.enable_app_entrypoint ? [
    "/consul/consul-ecs", "app-entrypoint", "-shutdown-delay", "${var.application_shutdown_delay_seconds}s",
  ] : null
  app_mountpoints = local.enable_app_entrypoint ? [local.consul_data_mount] : []
  service_name    = var.consul_service_name != "" ? var.consul_service_name : var.family

  // Optionally, users can provide a partition and namespace for the service.
  partition_tag = var.consul_partition != "" ? { "consul.hashicorp.com/partition" = var.consul_partition } : {}
  namespace_tag = var.consul_namespace != "" ? { "consul.hashicorp.com/namespace" = var.consul_namespace } : {}

  // container_defs_with_depends_on is the app's container definitions with their dependsOn keys
  // modified to add in dependencies on consul-ecs-mesh-init and sidecar-proxy.
  // We add these dependencies in so that the app containers don't start until the proxy
  // is ready to serve traffic.
  container_defs_with_depends_on = [for def in var.container_definitions :
    merge(
      def,
      {
        dependsOn = flatten(
          concat(
            lookup(def, "dependsOn", []),
            [
              {
                containerName = "consul-ecs-mesh-init"
                condition     = "SUCCESS"
              },
              {
                containerName = "sidecar-proxy"
                condition     = "HEALTHY"
              }
            ]
        ))
      },
      {
        // Use the def.entryPoint, if defined. Else, use the app_entrypoint, which is null by default.
        entryPoint = lookup(def, "entryPoint", local.app_entrypoint)
        mountPoints = flatten(
          concat(
            lookup(def, "mountPoints", []),
            local.app_mountpoints,
          )
        )
      }
    )
  ]

  defaulted_check_containers = length(var.checks) == 0 ? [for def in local.container_defs_with_depends_on : def.name
  if contains(keys(def), "essential") && contains(keys(def), "healthCheck")] : []

  consul_agent_defaults_hcl = templatefile(
    "${path.module}/templates/consul_agent_defaults.hcl.tpl",
    {
      gossip_encryption_enabled = local.gossip_encryption_enabled
      retry_join                = var.retry_join
      tls                       = var.tls
      acls                      = var.acls
      partition                 = var.consul_partition
    }
  )

  secret_name = var.consul_partition != "" ? "${var.acl_secret_name_prefix}-${local.service_name}-${var.consul_namespace}-${var.consul_partition}" : "${var.acl_secret_name_prefix}-${local.service_name}"
}

resource "aws_secretsmanager_secret" "service_token" {
  count                   = var.acls ? 1 : 0
  name                    = local.secret_name
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "service_token" {
  count         = var.acls ? 1 : 0
  secret_id     = aws_secretsmanager_secret.service_token[count.index].id
  secret_string = jsonencode({})
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.family
  requires_compatibilities = var.requires_compatibilities
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn
  volume {
    name = local.consul_data_volume_name
  }

  volume {
    name = local.consul_binary_volume_name
  }

  dynamic "volume" {
    for_each = var.volumes
    content {
      name      = volume.value["name"]
      host_path = lookup(volume.value, "host_path", null)

      dynamic "docker_volume_configuration" {
        for_each = contains(keys(volume.value), "docker_volume_configuration") ? [
          volume.value["docker_volume_configuration"]
        ] : []
        content {
          autoprovision = lookup(docker_volume_configuration.value, "autoprovision", null)
          driver_opts   = lookup(docker_volume_configuration.value, "driver_opts", null)
          driver        = lookup(docker_volume_configuration.value, "driver", null)
          labels        = lookup(docker_volume_configuration.value, "labels", null)
          scope         = lookup(docker_volume_configuration.value, "scope", null)
        }
      }

      dynamic "efs_volume_configuration" {
        for_each = contains(keys(volume.value), "efs_volume_configuration") ? [
          volume.value["efs_volume_configuration"]
        ] : []
        content {
          file_system_id          = efs_volume_configuration.value["file_system_id"]
          root_directory          = lookup(efs_volume_configuration.value, "root_directory", null)
          transit_encryption      = lookup(efs_volume_configuration.value, "transit_encryption", null)
          transit_encryption_port = lookup(efs_volume_configuration.value, "transit_encryption_port", null)
          dynamic "authorization_config" {
            for_each = contains(keys(efs_volume_configuration.value), "authorization_config") ? [
              efs_volume_configuration.value["authorization_config"]
            ] : []
            content {
              access_point_id = lookup(authorization_config.value, "access_point_id", null)
              iam             = lookup(authorization_config.value, "iam", null)
            }
          }
        }
      }

      dynamic "fsx_windows_file_server_volume_configuration" {
        for_each = contains(keys(volume.value), "fsx_windows_file_server_volume_configuration") ? [
          volume.value["fsx_windows_file_server_volume_configuration"]
        ] : []

        content {
          // All fields required.
          file_system_id = fsx_windows_file_server_volume_configuration.value["file_system_id"]
          root_directory = fsx_windows_file_server_volume_configuration.value["root_directory"]
          dynamic "authorization_config" {
            for_each = contains(keys(fsx_windows_file_server_volume_configuration.value), "authorization_config") ? [
              fsx_windows_file_server_volume_configuration.value["authorization_config"]
            ] : []
            content {
              // All fields required.
              credentials_parameter = authorization_config.value["credentials_parameter"]
              domain                = authorization_config.value["domain"]
            }
          }
        }
      }
    }
  }

  tags = merge(
    var.tags,
    {
      "consul.hashicorp.com/mesh"           = "true"
      "consul.hashicorp.com/service-name"   = local.service_name
      "consul.hashicorp.com/module"         = "terraform-aws-consul-ecs"
      "consul.hashicorp.com/module-version" = local.version_string
    },
    local.partition_tag,
    local.namespace_tag,
  )

  container_definitions = jsonencode(
    flatten(
      concat(
        local.container_defs_with_depends_on,
        [
          {
            name             = "consul-ecs-mesh-init"
            image            = var.consul_ecs_image
            essential        = false
            logConfiguration = var.log_configuration
            command          = ["mesh-init"]
            mountPoints = [
              local.consul_data_mount_read_write,
              {
                sourceVolume  = local.consul_binary_volume_name
                containerPath = "/bin/consul-inject"
                readOnly      = true
              }
            ]
            cpu         = 0
            volumesFrom = []
            environment = [
              {
                name  = "CONSUL_ECS_CONFIG_JSON",
                value = local.encoded_config
              }
            ]
            linuxParameters = {
              initProcessEnabled = true
            }
            portMappings = []
            secrets = var.acls ? [
              {
                // TODO: Remove once switched to auth method
                name      = "CONSUL_HTTP_TOKEN",
                valueFrom = "${aws_secretsmanager_secret.service_token[0].arn}:token::"
              }
            ] : [],
          },
          {
            name             = "consul-client"
            image            = var.consul_image
            essential        = false
            portMappings     = []
            logConfiguration = var.log_configuration
            entryPoint       = ["/bin/sh", "-ec"]
            command = [replace(
              templatefile(
                "${path.module}/templates/consul_client_command.tpl",
                {
                  consul_agent_defaults_hcl      = local.consul_agent_defaults_hcl
                  consul_agent_configuration_hcl = var.consul_agent_configuration
                  tls                            = var.tls
                  acls                           = var.acls
                  consul_http_addr               = var.consul_http_addr
                  client_token_auth_method_name  = var.client_token_auth_method_name
                  consul_partition               = var.consul_partition
                  region                         = data.aws_region.current.name
                }
              ), "\r", "")
            ]
            mountPoints = [
              local.consul_data_mount_read_write,
              {
                sourceVolume  = local.consul_binary_volume_name
                containerPath = "/bin/consul-inject"
              }
            ]
            linuxParameters = {
              initProcessEnabled = true
            }
            cpu         = 0
            volumesFrom = []
            environment = [
              {
                name  = "CONSUL_DATACENTER"
                value = var.consul_datacenter
              }
            ]
            secrets = concat(
              var.tls ? [
                {
                  name      = "CONSUL_CACERT",
                  valueFrom = var.consul_server_ca_cert_arn
                }
              ] : [],
              local.gossip_encryption_enabled ? [
                {
                  name      = "CONSUL_GOSSIP_ENCRYPTION_KEY",
                  valueFrom = var.gossip_key_secret_arn
                }
              ] : [],
              var.acls ? [
                {
                  // TODO: Remove once switched to auth method
                  name      = "AGENT_TOKEN",
                  valueFrom = "${var.consul_client_token_secret_arn}:token::"
                }
              ] : [],
            )
          },
          {
            name             = "sidecar-proxy"
            image            = var.envoy_image
            essential        = false
            logConfiguration = var.log_configuration
            entryPoint       = ["/consul/consul-ecs", "envoy-entrypoint"]
            command          = ["envoy", "--config-path", "/consul/envoy-bootstrap.json"]
            portMappings     = []
            mountPoints = [
              local.consul_data_mount
            ]
            dependsOn = [
              {
                containerName = "consul-ecs-mesh-init"
                condition     = "SUCCESS"
              },
            ]
            healthCheck = {
              command  = ["nc", "-z", "127.0.0.1", "20000"]
              interval = 30
              retries  = 3
              timeout  = 5
            }
            cpu         = 0
            volumesFrom = []
            environment = []
            ulimits = [{
              name = "nofile"
              // Note: 2^20 (1048576) is the maximum.
              // Going higher would need sysctl settings: https://github.com/aws/containers-roadmap/issues/460.
              // AWS API will accept invalid values, and you will see a CannotStartContainerError at runtime.
              softLimit = 1048576
              hardLimit = 1048576
            }]
          },
        ],
        length(local.defaulted_check_containers) > 0 ? [{
          name             = "consul-ecs-health-sync"
          image            = var.consul_ecs_image
          essential        = false
          logConfiguration = var.log_configuration
          command          = ["health-sync"]
          cpu              = 0
          volumesFrom      = []
          environment = [
            {
              name  = "CONSUL_ECS_CONFIG_JSON",
              value = local.encoded_config
            }
          ]
          portMappings = []
          dependsOn = [
            {
              containerName = "consul-ecs-mesh-init"
              condition     = "SUCCESS"
            },
          ]
          linuxParameters = {
            initProcessEnabled = true
          }
          secrets = var.acls ? [
            {
              // TODO: Remove once switched to auth method
              name      = "CONSUL_HTTP_TOKEN",
              valueFrom = "${aws_secretsmanager_secret.service_token[0].arn}:token::"
            }
          ] : []
        }] : [],
      )
    )
  )
}
