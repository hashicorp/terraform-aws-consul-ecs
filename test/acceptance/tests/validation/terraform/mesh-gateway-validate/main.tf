# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "kind" {
  type = string
}

variable "enable_mesh_gateway_wan_federation" {
  type = bool
}

variable "tls" {
  type = bool
}

variable "security_groups" {
  type    = list(string)
  default = []
}

variable "lb_enabled" {
  description = "Whether to create an Elastic Load Balancer for the task to allow public ingress to the gateway."
  type        = bool
  default     = false
}

variable "lb_vpc_id" {
  description = "The VPC identifier for the load balancer. Required when lb_enabled is true."
  type        = string
  default     = ""
}

variable "lb_subnets" {
  description = "Subnet IDs to attach to the load balancer. These must be public subnets if you wish to access the load balancer externally. Required when lb_enabled is true."
  type        = list(string)
  default     = []
}

variable "wan_address" {
  type    = string
  default = ""
}

variable "lb_create_security_group" {
  type    = bool
  default = true
}

variable "lb_modify_security_group" {
  type    = bool
  default = false
}

variable "lb_modify_security_group_id" {
  type    = string
  default = ""
}

variable "gateway_count" {
  type    = number
  default = 1
}

module "test_gateway" {
  source                             = "../../../../../../modules/gateway-task"
  family                             = "family"
  ecs_cluster_arn                    = "cluster"
  subnets                            = ["subnets"]
  security_groups                    = var.security_groups
  enable_transparent_proxy           = false
  kind                               = var.kind
  gateway_count                      = var.gateway_count
  consul_server_hosts                = "localhost:8500"
  enable_mesh_gateway_wan_federation = var.enable_mesh_gateway_wan_federation
  tls                                = var.tls
  wan_address                        = var.wan_address
  lb_enabled                         = var.lb_enabled
  lb_vpc_id                          = var.lb_vpc_id
  lb_subnets                         = var.lb_subnets
  lb_create_security_group           = var.lb_create_security_group
  lb_modify_security_group           = var.lb_modify_security_group
  lb_modify_security_group_id        = var.lb_modify_security_group_id
}
