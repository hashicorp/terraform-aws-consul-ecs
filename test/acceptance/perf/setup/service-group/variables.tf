variable "name" {
  type = string
}

variable "suffix" {
  type = string
}

variable "gossip_key_secret_arn" {
  type = string
}

variable "datadog_api_key" {
  type = string
}

variable "consul_ecs_image" {
  type = string
}

variable "region" {
  type = string
}

variable "additional_task_role_policies" {
  type = list(string)
}

variable "log_group_name" {
  type = string
}

variable "ca_cert_arn" {
  type = string
}
variable "tags" {
  type        = map(any)
  default     = {}
  description = "Tags to attach to the created resources."
}

variable "launch_type" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}


variable "cluster_arn" {
  type = string
}

variable "consul_client_token_secret_arn" {
  type = string
}

variable "server_instances_per_service_group" {
  type = number
}
