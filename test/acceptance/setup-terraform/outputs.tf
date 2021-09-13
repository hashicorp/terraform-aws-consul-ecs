output "ecs_cluster_arn_fargate" {
  value = aws_ecs_cluster.fargate.arn
}

output "ecs_cluster_arn_ec2" {
  value = aws_ecs_cluster.ec2.arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "subnets" {
  value = module.vpc.private_subnets
}

output "suffix" {
  value = random_string.suffix.result
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.log_group.name
}

output "region" {
  value = var.region
}

output "tags" {
  value = var.tags
}
