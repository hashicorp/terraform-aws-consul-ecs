# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "volumes" {
  type = any
}

module "test_gateway" {
  source                   = "../../../../../../modules/gateway-task"
  family                   = "family"
  kind                     = "terminating-gateway"
  ecs_cluster_arn          = "cluster"
  subnets                  = ["subnets"]
  volumes                  = var.volumes
  consul_server_hosts      = "consul.dc1"
  lb_create_security_group = false

  enable_transparent_proxy = false
}
