output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "task_role_arn" {
  value = var.task_role_arn != "" ? var.task_role_arn : aws_iam_role.task[0].arn
}

output "execution_role_arn" {
  value = var.execution_role_arn != "" ? var.execution_role_arn : aws_iam_role.execution[0].arn
}

output "task_tags" {
  value = aws_ecs_task_definition.this.tags_all
}

