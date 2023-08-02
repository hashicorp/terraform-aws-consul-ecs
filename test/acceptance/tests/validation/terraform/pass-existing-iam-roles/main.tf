# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

// We test this with a 'terraform apply'.
// It creates roles and the task definition.

provider "aws" {
  region = "us-west-2"
}

output "suffix" {
  value = local.suffix
}

output "create_roles_family" {
  value = local.create_roles_family
}

output "pass_roles_family" {
  value = local.pass_roles_family
}

output "create_roles_task_definition_arn" {
  value = module.test_client_create_new_roles.task_definition_arn
}

output "pass_roles_task_definition_arn" {
  value = module.test_client_pass_existing_roles.task_definition_arn
}


resource "random_string" "suffix" {
  length  = 8
  special = false
}

locals {
  suffix              = lower(random_string.suffix.result)
  create_roles_family = "consul-ecs-test-create-roles-${local.suffix}"
  pass_roles_family   = "consul-ecs-test-pass-existing-roles-${local.suffix}"
  container_definitions = [{
    name  = "basic"
    image = "fake"
  }]
}

module "test_client_create_new_roles" {
  source                = "../../../../../../modules/mesh-task"
  family                = local.create_roles_family
  log_configuration     = null
  container_definitions = local.container_definitions
  consul_server_hosts   = "consul.dc1"
  outbound_only         = true

  // Roles are not passed. This tests the default values for create_task_role,
  // create_execution_role, task_role, and execution_role.
}

module "test_client_pass_existing_roles" {
  source                = "../../../../../../modules/mesh-task"
  family                = local.pass_roles_family
  log_configuration     = null
  container_definitions = local.container_definitions
  consul_server_hosts   = "consul.dc1"
  outbound_only         = true

  create_task_role      = false
  create_execution_role = false
  task_role             = data.aws_iam_role.task
  execution_role        = data.aws_iam_role.execution
}

data "aws_iam_role" "task" {
  name = aws_iam_role.task.name
}

data "aws_iam_role" "execution" {
  name = aws_iam_role.execution.name
}

resource "aws_iam_role" "task" {
  name = "consul-ecs-test-pass-task-role-${local.suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}


resource "aws_iam_role" "execution" {
  name = "consul-ecs-test-pass-execution-role-${local.suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}
