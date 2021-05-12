variable "ecs_cluster_arn" {
  description = "ARN of pre-existing ECS cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs into which the task should be deployed."
  type        = list(string)
}

variable "load_balancer_enabled" {
  description = "Whether to create an ALB for the server task. Useful for accessing the UI."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID ECS cluster is running in."
  type        = string
}

variable "lb_subnets" {
  description = "Subnet IDs to attach to the load balancer."
  type        = list(string)
}

variable "lb_ingress_rule_cidr_blocks" {
  type    = list(string)
  default = null
}

variable "lb_ingress_rule_security_groups" {
  type    = list(string)
  default = null
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "hashicorp/consul:1.9.5"
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
  default     = "consul-server"
}

variable "tags" {
  description = "List of tags to add to all resources that support tags. Each element in the list is a map containing keys 'key', 'value', and 'propagate_at_launch' mapped to the respective values."
  type        = list(object({ key : string, value : string, propagate_at_launch : bool }))
  default     = []
}
