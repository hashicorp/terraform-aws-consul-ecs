output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "security_group_id" {
  value = aws_security_group.this.id
}
