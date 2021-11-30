output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "task_role_id" {
  value = local.task_role_id
}

output "execution_role_id" {
  value = local.execution_role_id
}

output "task_tags" {
  value = aws_ecs_task_definition.this.tags_all
}

