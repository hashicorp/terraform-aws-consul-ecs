variable "ecs_cluster_arn" {
  description = "ARN of pre-existing ECS cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs into which the task should be deployed."
  type        = list(string)
}

variable "lb_enabled" {
  description = "Whether to create an ALB for the server task. Useful for accessing the UI."
  type        = bool
  default     = false
}

variable "lb_vpc_id" {
  description = "VPC ID for ALB."
  type        = string
  default     = null
}

variable "lb_subnets" {
  description = "Subnet IDs to attach to the load balancer. NOTE: These must be public subnets if you wish to access the load balancer externally."
  type        = list(string)
  default     = null
}

variable "lb_ingress_rule_cidr_blocks" {
  description = "CIDR blocks that are allowed access to the load balancer."
  type        = list(string)
  default     = null
}

variable "lb_ingress_rule_security_groups" {
  description = "Security groups that are allowed access to the load balancer."
  type        = list(string)
  default     = null
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "docker.io/hashicorp/consul:1.9.5"
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
  default     = "consul-server"
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}
