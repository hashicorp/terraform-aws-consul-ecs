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

