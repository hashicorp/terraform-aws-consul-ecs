# Copyright IBM Corp. 2021, 2026
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "enable_consul_image_version_metadata" {
  type    = bool
  default = false
}

variable "consul_ecs_image_version" {
  type    = string
  default = "0.10.0"
}

variable "consul_dataplane_image_version" {
  type    = string
  default = "2.0.1"
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  consul_server_hosts = "consul.dc1.host"
  outbound_only       = true

  enable_transparent_proxy             = false
  enable_consul_image_version_metadata = var.enable_consul_image_version_metadata
  consul_ecs_image_version             = var.consul_ecs_image_version
  consul_dataplane_image_version       = var.consul_dataplane_image_version
}
