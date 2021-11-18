output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "task_role_id" {
  value = local.create_task_role ? aws_iam_role.task[0].id : var.task_role.id
}

output "execution_role_id" {
  value = local.create_execution_role ? aws_iam_role.execution[0].id : var.task_role.id
}

output "task_tags" {
  value = aws_ecs_task_definition.this.tags_all
}

