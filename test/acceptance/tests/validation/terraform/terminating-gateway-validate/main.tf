# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "kind" {
  type = string
}

variable "gateway_count" {
  type    = number
  default = 1
}

module "test_gateway" {
  source                      = "../../../../../../modules/gateway-task"
  family                      = "family"
  ecs_cluster_arn             = "cluster"
  subnets                     = ["subnets"]
  kind                        = var.kind
  gateway_count               = var.gateway_count
  consul_server_hosts         = "localhost:8500"
  tls                         = true
  lb_create_security_group    = false
}
