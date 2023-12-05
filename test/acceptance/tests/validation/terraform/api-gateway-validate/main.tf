# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "kind" {
  type = string
}

variable "lb_enabled" {
  description = "Whether to create an Elastic Load Balancer for the task to allow public ingress to the gateway."
  type        = bool
  default     = false
}

variable "lb_vpc_id" {
  type    = string
  default = ""
}

variable "lb_subnets" {
  type    = list(string)
  default = []
}

variable "custom_lb_config" {
  type    = any
  default = []
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
  lb_enabled                  = var.lb_enabled
  lb_vpc_id                   = var.lb_vpc_id
  lb_subnets                  = var.lb_subnets
  custom_load_balancer_config = var.custom_lb_config
  lb_create_security_group    = var.lb_enabled
}
