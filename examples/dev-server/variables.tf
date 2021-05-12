variable "ecs_cluster_arn" {
  description = "ARN of pre-existing ECS cluster."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID ECS cluster is running in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs into which the tasks should be deployed."
  type        = list(string)
}

variable "lb_subnet_ids" {
  description = "Subnet IDs to attach to the Consul server and example application load balancers."
  type        = list(string)
}

variable "lb_ingress_rule_cidr_blocks" {
  type = list(string)
}
