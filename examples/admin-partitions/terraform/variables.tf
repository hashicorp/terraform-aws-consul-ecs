variable "region" {
  default     = "us-west-2"
  description = "AWS region"
}

variable "tags" {
  type        = map(any)
  default     = {}
  description = "Tags to attach to the created resources."
}

variable "consul_image" {
  description = "Consul Docker image."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul-enterprise:1.11.4-ent"
}

variable "consul_ecs_image" {
  description = "Consul ECS image to use."
  type        = string
  default     = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:3669cbe"
}

variable "client_partition" {
  description = "The Consul partition to deploy the example client into."
  type        = string
  default     = "part1"
}

variable "client_namespace" {
  description = "The Consul namespace to deploy the example client into."
  type        = string
  default     = "ns1"
}

variable "server_partition" {
  description = "The Consul partition to deploy the example server into."
  type        = string
  default     = "part2"
}

variable "server_namespace" {
  description = "The Consul namespace to deploy the example server into."
  type        = string
  default     = "ns2"
}
