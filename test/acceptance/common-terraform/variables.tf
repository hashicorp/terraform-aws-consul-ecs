variable "ecs_cluster_arn" {
  type        = string
  description = "Cluster ARN of ECS cluster."
}
variable "private_subnets" {
  type        = list(string)
  description = "Private subnets to deploy tasks into."
}

variable "suffix" {
  type        = string
  description = "Suffix to add to all resource names."
}

variable "region" {
  type        = string
  description = "Region."
}

variable "log_group_name" {
  type        = string
  description = "Name for cloudwatch log group."
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
}

variable "launch_type" {
  description = "Whether to launch tasks on Fargate or EC2"
  type        = string
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
}

variable "retry_join" {
  description = "retry_join option for mesh-tasks"
  type        = string
}

variable "consul_server_http_addr" {
  description = "Consul server url (e.g. https://consul.example.com:8501)"
  type        = string
}

variable "secure" {
  description = "Whether to create all resources in a secure installation (with TLS, ACLs and gossip encryption)."
  type        = bool
}

variable "consul_server_ca_cert_arn" {
  description = "Secret containing the Consul server CA cert."
  type        = string
}

variable "consul_bootstrap_token_secret_arn" {
  description = "Secret containing the Consul bootstrap token."
  type        = string
}

variable "consul_gossip_key_secret_arn" {
  description = "Secret containing the Consul bootstrap token."
  type        = string
}

variable "server_service_name" {
  description = "The service name for the test_server"
  type        = string
}
