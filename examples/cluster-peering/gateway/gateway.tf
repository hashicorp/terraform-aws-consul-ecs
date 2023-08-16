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
}
