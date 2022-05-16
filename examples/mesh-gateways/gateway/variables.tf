variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
}

variable "datacenter" {
  description = "Name of the consul datacenter."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "vpc" {
  description = "VPC object from terraform-aws-modules/vpc/aws module."
  type = object({
    vpc_id                    = string
    default_security_group_id = string
  })
}

variable "private_subnets" {
  description = "List of private subnet ids."
  type        = list(string)
}

variable "public_subnets" {
  description = "List of public subnet ids."
  type        = list(string)
}

variable "primary_datacenter" {
  description = "Primary datacenter for the consul agent (required to match across datacenters for CA to work right with WAN fed)."
  type        = string
  default     = ""
}

variable "cluster" {
  description = "The ARN of the ECS cluster to deploy the mesh gateway into."
  type        = string
}

variable "retry_join" {
  type = list(string)
}

variable "log_group_name" {
  type = string
}

variable "enable_mesh_gateway_wan_federation" {
  description = "Controls whether or not WAN federation via mesh gateways is enabled. Default is false."
  type        = bool
  default     = false
}
