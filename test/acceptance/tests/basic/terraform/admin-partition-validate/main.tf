# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = "us-west-2"
}

variable "partition" {
  type    = string
  default = ""
}

variable "namespace" {
  type    = string
  default = ""
}

module "test_client" {
  source = "../../../../../../modules/mesh-task"
  family = "family"
  container_definitions = [{
    name = "basic"
  }]
  outbound_only = true
  retry_join    = ["test"]

  consul_partition = var.partition
  consul_namespace = var.namespace
}
