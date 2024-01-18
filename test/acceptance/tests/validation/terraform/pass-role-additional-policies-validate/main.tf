# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

// We test this with a 'terraform plan' only.

provider "aws" {
  region = "us-west-2"
}

variable "test_execution_role" {
  description = "By default, we test with the task role. Set this to true to test with the execution role."
  type        = bool
  default     = false
}


locals {
  container_definitions = [{
    name  = "basic"
    image = "fake"
  }]
}

module "task_role_test" {
  count = var.test_execution_role ? 0 : 1

  source                = "../../../../../../modules/mesh-task"
  family                = "family-1"
  log_configuration     = null
  container_definitions = local.container_definitions
  consul_server_hosts   = "consul.dc1"
  outbound_only         = true

  create_task_role              = false
  additional_task_role_policies = ["arn:aws:iam::000000000000:policy/some-policy"]
  task_role = {
    id  = "my-task-role"
    arn = "arn:aws:iam::000000000000:role/some-role"
  }
}

module "execution_role_test" {
  count = var.test_execution_role ? 1 : 0

  source                = "../../../../../../modules/mesh-task"
  family                = "family-2"
  log_configuration     = null
  container_definitions = local.container_definitions
  consul_server_hosts   = "consul.dc1"
  outbound_only         = true

  create_execution_role              = false
  additional_execution_role_policies = ["arn:aws:iam::000000000000:policy/some-policy"]
  execution_role = {
    id  = "my-task-role"
    arn = "arn:aws:iam::000000000000:role/some-role"
  }

  enable_transparent_proxy = false
}
