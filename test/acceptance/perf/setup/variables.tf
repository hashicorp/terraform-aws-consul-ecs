variable "region" {
  default     = "us-west-2"
  description = "AWS region"
}

variable "role_arn" {
  default     = ""
  description = "AWS role for the AWS provider to assume when running these templates."
}

variable "tags" {
  type        = map(any)
  default     = {}
  description = "Tags to attach to the created resources."
}


variable "datadog_api_key" {}

variable "launch_type" {
  type        = string
  description = "The ECS launch type"
  default     = "FARGATE"
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:latest"
}

variable "service_groups" {
  description = "The number of service groups"
  type        = number
}

variable "server_instances_per_service_group" {
  description = "The number of server instances per service group"
  type        = number
}

variable "client_instances_per_service_group" {
  description = "The number of client instances per service group"
  type        = number
  default     = 1
}

variable "lb_ingress_ip" {
  type = string
}
