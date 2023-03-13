# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "task_role_id" {
  value = aws_iam_role.task.id
}

output "execution_role_id" {
  value = aws_iam_role.execution.id
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_tags" {
  value = aws_ecs_task_definition.this.tags_all
}

output "wan_address" {
  value = local.wan_address
}

output "wan_port" {
  value = local.wan_port
}

output "lb_security_group_id" {
  value = var.lb_enabled && var.lb_create_security_group ? aws_security_group.this[0].id : null
}
