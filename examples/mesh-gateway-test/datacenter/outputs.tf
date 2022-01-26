output "ecs_cluster" {
  value = aws_ecs_cluster.this
}

output "dev_consul_server" {
  value = module.dev_consul_server
}

output "log_group" {
  value = aws_cloudwatch_log_group.log_group
}

output "datacenter" {
  value = var.datacenter
}

output "private_subnets" {
  value = var.private_subnets
}

output "public_subnets" {
  value = var.public_subnets
}
