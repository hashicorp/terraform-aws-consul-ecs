# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "mesh-gateway"
    }
  }
}

module "mesh_gateway" {
  source                        = "../../../modules/gateway-task"
  family                        = var.name
  ecs_cluster_arn               = var.cluster
  subnets                       = var.private_subnets
  security_groups               = [var.vpc.default_security_group_id]
  log_configuration             = local.log_config
  consul_server_hosts           = var.consul_server_address
  kind                          = "mesh-gateway"
  tls                           = true
  consul_ca_cert_arn            = var.ca_cert_arn
  additional_task_role_policies = var.additional_task_role_policies

  acls = true

  lb_enabled = true
  lb_subnets = var.public_subnets
  lb_vpc_id  = var.vpc.vpc_id

  consul_ecs_image = var.consul_ecs_image
  consul_partition = var.consul_partition
}

# We must wait for the mesh gateway belonging to become healthy before
# the callers can initiating peering between datacenters via gateways.
# on the /v1/health/check/:service API to identify the readiness.
# We also add a custom sleep for around a minute to make sure to avoid
# any race conditions that might prevent traffic from flowing through
# the gateways.
resource "null_resource" "wait_for_mesh_gateway" {
  provisioner "local-exec" {
    command = <<EOT
stopTime=$(($(date +%s) + ${var.mesh_gateway_readiness_timeout})) ; \
while [ $(date +%s) -lt $stopTime ] ; do \
  sleep 10 ; \
  meshGatewayStatus=$(curl -H "Authorization: Bearer ${var.consul_server_bootstrap_token}" http://${var.consul_server_lb_dns_name}:8500/v1/health/checks/${var.name}?partition=${var.consul_partition} | jq -r ".[0].Status")
  [ "$meshGatewayStatus" = passing ] && break; \
done ; \
sleep 60
EOT
  }
}