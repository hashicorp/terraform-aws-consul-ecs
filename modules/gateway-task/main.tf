data "aws_region" "current" {}

locals {
  // Must be updated for each release, and after each release to return to a "-dev" version.
  version_string = "0.5.0-dev"

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
  // Note that for gateway tasks the namespace is always "default" or empty.
  partition_tag = var.consul_partition != "" ? { "consul.hashicorp.com/partition" = var.consul_partition } : {}
  namespace_tag = local.consul_namespace != "" ? { "consul.hashicorp.com/namespace" = local.consul_namespace } : {}

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


  lan_port    = var.lan_port != 0 ? var.lan_port : 8443
  wan_port    = var.wan_port != 0 ? var.wan_port : local.lan_port
  wan_address = var.lb_enabled ? aws_lb.this[0].dns_name : var.wan_address

  load_balancer = var.lb_enabled ? [{
    target_group_arn = aws_lb_target_group.this[0].arn
    container_name   = "sidecar-proxy"
    container_port   = local.lan_port
  }] : []

  security_groups = var.lb_create_security_group ? concat(
    var.security_groups,
    [aws_security_group.this[0].id]
  ) : var.security_groups
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
                containerPort = local.lan_port
                hostPort      = local.lan_port
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
              command  = ["nc", "-z", "127.0.0.1", tostring(local.lan_port)]
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
        // health-sync is enabled if acls are enabled, in order to run 'consul logout' to cleanup tokens when the task stops
        var.acls ? [{
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
          mountPoints = [
            local.consul_data_mount
          ]
          dependsOn = [
            {
              containerName = "consul-ecs-mesh-init"
              condition     = "SUCCESS"
            },
          ]
          linuxParameters = {
            initProcessEnabled = true
          }
        }] : [],
      )
    )
  )
}

resource "aws_ecs_service" "this" {
  name            = local.service_name
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
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
