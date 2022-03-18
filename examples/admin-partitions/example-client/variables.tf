variable "region" {
  type        = string
  description = "Region."
}

variable "ecs_cluster_arn" {
  type        = string
  description = "ARN of the ECS cluster."
}

variable "subnets" {
  type        = list(string)
  description = "Subnets to deploy into."
}

variable "launch_type" {
  description = "Whether to launch tasks on Fargate or EC2"
  type        = string
}

variable "suffix" {
  type        = string
  default     = ""
  description = "Suffix to add to all resource names."
}

variable "log_group_name" {
  type        = string
  description = "Name for cloudwatch log group."
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "hcp_private_endpoint" {
  description = "URL of the HCP Consul cluster."
  type = string
}

variable "bootstrap_token_arn" {
  description = "ARN of the secret holding the Consul bootstrap token."
  type = string
}

variable "consul_ca_cert_arn" {
  description = "ARN of the secret holding the Consul CA certificate."
  type = string
}

variable "gossip_key_arn" {
  description = "ARN of the secret holding the Consul gossip key."
  type = string
}

variable "retry_join" {
  description = "The retry join string for connecting to the Consul server."
  type = list(string)
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul-enterprise:1.11.4-ent"
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:latest"
}

variable "partition" {
  description = "The Consul partition to deploy services into."
  type        = string
  default     = "default"
}

variable "namespace" {
  description = "The namespace to deploy services into."
  type        = string
  default     = "default"
}

variable "upstream_name" {
  description = "The name of the upstream service."
  type        = string
}

variable "upstream_partition" {
  description = "The Consul partition of the upstream service."
  type        = string
  default     = "default"
}

variable "upstream_namespace" {
  description = "The namespace of the upstream service."
  type        = string
  default     = "default"
}

