# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

data "aws_region" "current" {}

locals {
  // Must be updated for each release, and after each release to return to a "-dev" version.
  version_string = "0.8.0-dev"

  consul_data_volume_name = "consul_data"
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

  // Lower case service name is required. var.consul_service_name is validated to be lower case, while the task family is forced to lower case
  service_name = var.consul_service_name != "" ? var.consul_service_name : lower(var.family)

  // Optionally, users can provide a partition and namespace for the service.
  partition_tag = var.consul_partition != "" ? { "consul.hashicorp.com/partition" = var.consul_partition } : {}
  namespace_tag = var.consul_namespace != "" ? { "consul.hashicorp.com/namespace" = var.consul_namespace } : {}

  // container_defs_with_depends_on is the app's container definitions with their dependsOn keys
  // modified to add in dependencies on consul-ecs-control-plane and consul-dataplane.
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
                containerName = "consul-ecs-control-plane"
                condition     = "HEALTHY"
              },
              {
                containerName = "consul-dataplane"
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

  https_ca_cert_arn = var.consul_https_ca_cert_arn != "" ? var.consul_https_ca_cert_arn : var.consul_ca_cert_arn
  grpc_ca_cert_arn  = var.consul_grpc_ca_cert_arn != "" ? var.consul_grpc_ca_cert_arn : var.consul_ca_cert_arn

  defaulted_check_containers = [for def in local.container_defs_with_depends_on : def.name
  if contains(keys(def), "essential") && contains(keys(def), "healthCheck") && (try(def.healthCheck, null) != null)]
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
            name             = "consul-ecs-control-plane"
            image            = var.consul_ecs_image
            essential        = false
            logConfiguration = var.log_configuration
            command          = ["control-plane"]
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
            healthCheck = {
              command  = ["CMD-SHELL", "curl localhost:10000/consul-ecs/health"] # consul-ecs-control-plane exposes a listener on 10000 to indicate it's readiness
              interval = 30
              retries  = 10
              timeout  = 5
            }
            secrets = flatten(
              concat(
                var.tls ? [
                  concat(
                    local.https_ca_cert_arn != "" ? [
                      {
                        name      = "CONSUL_HTTPS_CACERT_PEM"
                        valueFrom = local.https_ca_cert_arn
                      },
                    ] : [],
                    local.grpc_ca_cert_arn != "" ? [
                      {
                        name      = "CONSUL_GRPC_CACERT_PEM"
                        valueFrom = local.grpc_ca_cert_arn
                      }
                    ] : [],
                    []
                  )
                ] : [],
                []
              )
            )
          },
          {
            name             = "consul-dataplane"
            image            = var.consul_dataplane_image
            essential        = false
            logConfiguration = var.log_configuration
            entryPoint       = ["/consul/consul-ecs", "envoy-entrypoint"]
            command          = ["consul-dataplane", "-config-file", "/consul/consul-dataplane.json"] # consul-ecs-control-plane dumps the dataplane's config into consul-dataplane.json
            portMappings     = []
            mountPoints = [
              local.consul_data_mount
            ]
            dependsOn = [
              {
                containerName = "consul-ecs-control-plane"
                condition     = "HEALTHY"
              },
            ]
            healthCheck = {
              command  = ["/consul/consul-ecs", "net-dial", format("127.0.0.1:%d", var.envoy_readiness_port)]
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
      )
    )
  )
}