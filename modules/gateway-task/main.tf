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

  service_name = var.consul_service_name != "" ? var.consul_service_name : var.family

  // Optionally, users can provide a partition and namespace for the service.
  // Note that for gateway tasks the namespace is always "default" or empty.
  partition_tag = var.consul_partition != "" ? { "consul.hashicorp.com/partition" = var.consul_partition } : {}
  namespace_tag = local.consul_namespace != "" ? { "consul.hashicorp.com/namespace" = local.consul_namespace } : {}


  lan_port    = var.lan_port != 0 ? var.lan_port : 8443
  wan_port    = var.wan_port != 0 ? var.wan_port : local.lan_port
  wan_address = var.lb_enabled ? aws_lb.this[0].dns_name : var.wan_address

  load_balancer = var.lb_enabled ? [{
    target_group_arn = aws_lb_target_group.this[0].arn
    container_name   = "consul-dataplane"
    container_port   = local.lan_port
  }] : var.custom_load_balancer_config

  security_groups = var.lb_create_security_group ? concat(
    var.security_groups,
    [aws_security_group.this[0].id]
  ) : var.security_groups

  mount_points = length(var.volumes) > 0 ? [
    for volume in var.volumes : {
      sourceVolume  = volume["name"]
      containerPath = lookup(volume, "host_path", null)
      readOnly      = lookup(volume, "read_only", true)
    }
  ] : []

  https_ca_cert_arn = var.consul_https_ca_cert_arn != "" ? var.consul_https_ca_cert_arn : var.consul_ca_cert_arn
  grpc_ca_cert_arn  = var.consul_grpc_ca_cert_arn != "" ? var.consul_grpc_ca_cert_arn : var.consul_ca_cert_arn
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.family
  requires_compatibilities = var.requires_compatibilities
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  volume {
    name = local.consul_data_volume_name
  }

  volume {
    name = local.consul_binary_volume_name
  }


  dynamic "volume" {
    for_each = var.volumes
    content {
      name = volume.value["name"]

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
        [
          {
            name             = "consul-ecs-mesh-init"
            image            = var.consul_ecs_image
            essential        = false
            logConfiguration = var.log_configuration
            command          = ["mesh-init"]
            mountPoints = concat(
              [
                local.consul_data_mount_read_write,
                {
                  sourceVolume  = local.consul_binary_volume_name
                  containerPath = "/bin/consul-inject"
                  readOnly      = true
                }
              ]
            )
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
            essential        = true
            logConfiguration = var.log_configuration
            entryPoint       = ["/consul/consul-ecs", "envoy-entrypoint"]
            command          = ["consul-dataplane", "-config-file", "/consul/consul-dataplane.json"] # consul-ecs-mesh-init dumps the dataplane's config into consul-dataplane.json
            portMappings = [
              {
                containerPort = local.lan_port
                hostPort      = local.lan_port
                protocol      = "tcp"
              }
            ]
            mountPoints = concat(
              [local.consul_data_mount],
              local.mount_points
            )
            dependsOn = [
              {
                containerName = "consul-ecs-mesh-init"
                condition     = "SUCCESS"
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
          {
            name             = "consul-ecs-health-sync"
            image            = var.consul_ecs_image
            essential        = false
            logConfiguration = var.log_configuration
            command          = ["health-sync"]
            user             = "5996"
            portMappings     = []
            mountPoints = concat(
              [local.consul_data_mount]
            )
            dependsOn = [
              {
                containerName = "consul-ecs-mesh-init"
                condition     = "SUCCESS"
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
        ],
      )
    )
  )
}

resource "aws_ecs_service" "this" {
  name            = local.service_name
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.gateway_count
  network_configuration {
    subnets          = var.subnets
    security_groups  = local.security_groups
    assign_public_ip = var.assign_public_ip
  }
  dynamic "load_balancer" {
    for_each = local.load_balancer
    content {
      target_group_arn = load_balancer.value["target_group_arn"]
      container_name   = load_balancer.value["container_name"]
      container_port   = load_balancer.value["container_port"]
    }
  }
  launch_type            = var.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

resource "aws_lb" "this" {
  count              = var.lb_enabled ? 1 : 0
  name               = local.service_name
  internal           = false
  load_balancer_type = "network"
  subnets            = var.lb_subnets
}

resource "aws_lb_target_group" "this" {
  count                = var.lb_enabled ? 1 : 0
  name                 = local.service_name
  port                 = tostring(local.wan_port)
  protocol             = "TCP"
  target_type          = "ip"
  vpc_id               = var.lb_vpc_id
  deregistration_delay = 120
  health_check {
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "this" {
  count             = var.lb_enabled ? 1 : 0
  load_balancer_arn = aws_lb.this[0].arn
  port              = tostring(local.wan_port)
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }
}

resource "aws_security_group" "this" {
  count       = var.lb_enabled && var.lb_create_security_group ? 1 : 0
  name        = local.service_name
  description = "Security group for ${local.service_name}"
  vpc_id      = var.lb_vpc_id
}

// The Terraform module automatically removes the allow all egress rule when creating a security group.
// When creating a security group we need to include the allow all egress rule.
resource "aws_security_group_rule" "lb_egress_rule" {
  count             = var.lb_enabled && var.lb_create_security_group ? 1 : 0
  type              = "egress"
  description       = "Egress rule for ${local.service_name}"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.this[0].id
}

resource "aws_security_group_rule" "lb_ingress_rule" {
  count             = var.lb_enabled && (var.lb_create_security_group || var.lb_modify_security_group) ? 1 : 0
  type              = "ingress"
  description       = "Ingress rule for ${local.service_name}"
  from_port         = local.wan_port
  to_port           = local.wan_port
  protocol          = "tcp"
  cidr_blocks       = var.lb_ingress_rule_cidr_blocks
  security_group_id = var.lb_create_security_group ? aws_security_group.this[0].id : var.lb_modify_security_group_id
}
