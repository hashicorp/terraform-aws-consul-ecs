variable "region" {
  description = "Region."
  type        = string
}

variable "suffix_1" {
  description = "Suffix to add to all resource names in cluster 1."
  type        = string
}

variable "suffix_2" {
  description = "Suffix to add to all resource names in cluster 2."
  type        = string
}

variable "ecs_cluster_arns" {
  type        = list(string)
  description = "ECS cluster ARNs. Two are required, and only the first two are used."

  validation {
    error_message = "Two ECS clusters are required."
    condition     = length(var.ecs_cluster_arns) >= 2
  }
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
  description = "Subnets to deploy into."
  type        = list(string)
}

variable "launch_type" {
  description = "Whether to launch tasks on Fargate or EC2"
  type        = string
}

variable "log_group_name" {
  description = "Name for cloudwatch log group."
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul-enterprise:1.12.6-ent"
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "docker.mirror.hashicorp.services/hashicorppreview/consul-ecs:0.5.1-dev"
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

variable "client_partition" {
  description = "The Consul partition that the client belongs to."
  type        = string
  default     = "part1"
}

variable "client_namespace" {
  description = "The Consul namespace that the client belongs to."
  type        = string
  default     = "ns1"
}

variable "server_partition" {
  description = "The Consul partition that the server belongs to."
  type        = string
  default     = "part2"
}

variable "server_namespace" {
  description = "The Consul namespace that the server belongs to."
  type        = string
  default     = "ns2"
}
