output "ecs_cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "launch_type" {
  value = var.launch_type
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

output "ingress_ip" {
  value = local.ingress_ip
}

output "lb_arn" {
  value = aws_lb.this.arn
}

output "lb_address" {
  value = "http://${aws_lb.this.dns_name}"
}
