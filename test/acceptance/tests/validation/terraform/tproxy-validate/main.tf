# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "requires_compatibilities" {
  description = "Set of launch types required by the task."
  type        = list(string)
}

variable "enable_transparent_proxy" {
  description = "Whether to enable or disable transparent proxy for the task"
  type        = bool
  default     = true
}

variable "enable_consul_dns" {
  description = "Whether to enable or disable Consul DNS for the task"
  type        = bool
  default     = true
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  outbound_only            = true
  consul_server_hosts      = "consul.dc1.host"
  requires_compatibilities = var.requires_compatibilities
  enable_transparent_proxy = var.enable_transparent_proxy
  enable_consul_dns        = var.enable_consul_dns
}
