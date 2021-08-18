output "client_token_secret_arn" {
  description = "The ARN of the secret for the Consul client ACL token."
  value       = aws_secretsmanager_secret.client_token.arn
}