output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "task_tags" {
  value = aws_ecs_task_definition.this.tags_all
}

