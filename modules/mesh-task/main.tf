data "aws_region" "current" {}

locals {
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
      }
    )
  ]

  defaulted_check_containers = length(var.checks) == 0 ? [for def in local.container_defs_with_depends_on : def.name
  if contains(keys(def), "essential") && contains(keys(def), "healthCheck")] : []

  upstreams_flag = join(",", [for upstream in var.upstreams : "${upstream["destination_name"]}:${upstream["local_bind_port"]}"])
}

resource "aws_iam_role" "task" {
  name = "${var.family}-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  inline_policy {
    name   = "exec"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
  }
}

resource "aws_iam_role_policy_attachment" "additional_task_policies" {
  count      = length(var.additional_task_role_policies)
  role       = aws_iam_role.task.id
  policy_arn = var.additional_task_role_policies[count.index]
}

resource "aws_iam_policy" "execution" {
  name        = "${var.family}-execution"
  path        = "/ecs/"
  description = "${var.family} mesh-task execution policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
%{if var.tls~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${var.consul_server_ca_cert_arn}"
      ]
    },
%{endif~}
%{if var.acls~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${var.consul_client_token_secret_arn}",
        "${aws_secretsmanager_secret.service_token[0].arn}"
      ]
    },
%{endif~}
%{if local.gossip_encryption_enabled~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${var.gossip_key_secret_arn}"
      ]
    },
%{endif~}
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "execution" {
  name = "${var.family}-execution"
  path = "/ecs/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.id
  policy_arn = aws_iam_policy.execution.arn
}

resource "aws_iam_role_policy_attachment" "additional_execution_policies" {
  count      = length(var.additional_execution_role_policies)
  role       = aws_iam_role.execution.id
  policy_arn = var.additional_execution_role_policies[count.index]
}

resource "aws_secretsmanager_secret" "service_token" {
  count                   = var.acls ? 1 : 0
  name                    = "${var.acl_secret_name_prefix}-${var.family}"
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
    { "consul.hashicorp.com/mesh" = "true" },
    { "consul.hashicorp.com/service-name" = var.consul_service_name != "" ? var.consul_service_name : var.family }
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
            command = [
              "mesh-init",
              "-envoy-bootstrap-dir=/consul",
              "-port=${var.port}",
              "-upstreams=${local.upstreams_flag}",
              "-checks=${jsonencode(var.checks)}",
              "-health-sync-containers=${join(",", local.defaulted_check_containers)}",
              "-tags=${join(",", var.consul_service_tags)}",
              "-meta=${jsonencode(var.consul_service_meta)}",
              "-service-name=${var.consul_service_name}"
            ]
            mountPoints = [
              local.consul_data_mount_read_write,
              {
                sourceVolume  = local.consul_binary_volume_name
                containerPath = "/bin/consul-inject"
                readOnly      = true
              }
            ]
            cpu          = 0
            volumesFrom  = []
            environment  = []
            portMappings = []
            secrets = var.acls ? [
              {
                name      = "CONSUL_HTTP_TOKEN",
                valueFrom = "${aws_secretsmanager_secret.service_token[0].arn}:token::"
              }
            ] : [],
          },
          {
            name      = "consul-client"
            image     = var.consul_image
            essential = false
            portMappings = [
              {
                containerPort = 8300
                hostPort      = 8300
                protocol      = "tcp"
              },
              {
                containerPort = 8300
                hostPort      = 8300
                protocol      = "udp"
              },
            ]
            logConfiguration = var.log_configuration
            entryPoint       = ["/bin/sh", "-ec"]
            command = [replace(
              templatefile(
                "${path.module}/templates/consul_client_command.tpl",
                {
                  gossip_encryption_enabled = local.gossip_encryption_enabled
                  retry_join                = var.retry_join
                  tls                       = var.tls
                  acls                      = var.acls
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
                  name      = "AGENT_TOKEN",
                  valueFrom = "${var.consul_client_token_secret_arn}:token::"
                }
              ] : [],
            )
          },
          {
            name             = "datadog-agent"
            image            = "datadog/agent:latest"
            essential        = true
            logConfiguration = var.log_configuration
            environment = [
              {
                name  = "DD_API_KEY"
                value = var.datadog_api_key
              },
              {
                name  = "ECS_FARGATE"
                value = "true"
              }
            ]
            dockerLabels = {
              "com.datadoghq.ad.check_names"  = "[\"openmetrics\"]"
              "com.datadoghq.ad.init_configs" = "[{}]"
              "com.datadoghq.ad.instances" = jsonencode([
                {
                  prometheus_url            = "http://%%host%%:9102/metrics"
                  namespace                 = "slow_cooker"
                  metrics                   = ["go_*", "latency*", "requests", "successes", "process*"]
                  send_distribution_buckets = true
                }
              ])
            }
          },
          {
            name             = "sidecar-proxy"
            image            = var.envoy_image
            essential        = false
            logConfiguration = var.log_configuration
            entrypoint       = ["/consul/consul-ecs", "envoy-entrypoint"]
            command          = ["envoy", "--config-path", "/consul/envoy-bootstrap.json"]
            portMappings = [
              {
                containerPort = 20000
                hostPort      = 20000
                protocol      = "tcp"
              },
            ]
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
          command = [
            "health-sync",
            "-health-sync-containers=${join(",", local.defaulted_check_containers)}",
            "-service-name=${var.consul_service_name}"
          ]
          cpu          = 0
          volumesFrom  = []
          environment  = []
          portMappings = []
          dependsOn = [
            {
              containerName = "consul-ecs-mesh-init"
              condition     = "SUCCESS"
            },
          ]
          secrets = var.acls ? [
            {
              name      = "CONSUL_HTTP_TOKEN",
              valueFrom = "${aws_secretsmanager_secret.service_token[0].arn}:token::"
            }
          ] : []
        }] : [],
      )
    )
  )
}
