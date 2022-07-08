variable "ecs_cluster_arn" {
  type        = string
  description = "Cluster ARN of ECS cluster."
}

variable "vpc_id" {
  description = "The ID of the VPC for all resources."
  type        = string
}

variable "route_table_ids" {
  description = "IDs of the route tables for peering with HVN."
  type        = list(string)
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
  default     = "nosuffix"
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
  default     = {}
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul-enterprise:1.12.2-ent"
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:latest"
}

variable "consul_public_endpoint_url" {
  description = "URL of the public Consul endpoint."
  type        = string
}

variable "consul_private_endpoint_url" {
  description = "URL of the private Consul endpoint."
  type        = string
}

variable "retry_join" {
  description = "Retry join string for the Consul client."
  type        = list(string)
}

variable "bootstrap_token_secret_arn" {
  description = "ARN of the secret holding the Consul bootstrap token."
  type        = string
}

variable "gossip_key_secret_arn" {
  description = "ARN of the secret holding the Consul gossip encryption key."
  type        = string
}

variable "consul_ca_cert_secret_arn" {
  description = "ARN of the secret holding the Consul CA certificate."
  type        = string
}

variable "audit_logging" {
  description = "Whether audit logging is enabled."
  type        = bool
  default     = false
}