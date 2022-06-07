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

  service_name = var.consul_service_name != "" ? var.consul_service_name : var.family

  // Optionally, users can provide a partition and namespace for the service.
  // Note that for gateway tasks the namespace is validated and can only be "default" or empty.
  partition_tag = var.consul_partition != "" ? { "consul.hashicorp.com/partition" = var.consul_partition } : {}
  namespace_tag = var.consul_namespace != "" ? { "consul.hashicorp.com/namespace" = var.consul_namespace } : {}

  consul_agent_defaults_hcl = templatefile(
    "${path.module}/templates/consul_agent_defaults.hcl.tpl",
    {
      gossip_encryption_enabled = local.gossip_encryption_enabled
      retry_join                = var.retry_join
      tls                       = var.tls
      acls                      = var.acls
      partition                 = var.consul_partition
      primary_datacenter        = var.consul_primary_datacenter
      enable_token_replication  = var.enable_acl_token_replication
    }
  )

  healthCheckPort = var.lan_port != 0 ? var.lan_port : 8443
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
              https                          = var.consul_https_ca_cert_arn != ""
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
              name      = "CONSUL_CACERT_PEM",
              valueFrom = var.consul_server_ca_cert_arn
            }
          ] : [],
          var.consul_https_ca_cert_arn != "" ? [
            {
              name      = "CONSUL_HTTPS_CACERT_PEM",
              valueFrom = var.consul_https_ca_cert_arn
            }
          ] : [],
          local.gossip_encryption_enabled ? [
            {
              name      = "CONSUL_GOSSIP_ENCRYPTION_KEY",
              valueFrom = var.gossip_key_secret_arn
            }
          ] : [],
        )
      },
      {
        name             = "sidecar-proxy"
        image            = var.envoy_image
        essential        = true
        logConfiguration = var.log_configuration
        command          = ["envoy", "--config-path", "/consul/envoy-bootstrap.json"]
        portMappings = [
          {
            containerPort = local.healthCheckPort
            hostPort      = local.healthCheckPort
            protocol      = "tcp"
          }
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
          command  = ["nc", "-z", "127.0.0.1", tostring(local.healthCheckPort)]
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
}
