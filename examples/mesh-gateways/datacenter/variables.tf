variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
}

variable "datacenter" {
  description = "Name of the consul datacenter."
  type        = string
  default     = "dc1"
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "lb_ingress_ip" {
  description = "Your IP. This is used in the load balancer security groups to ensure only you can access the Consul UI and example application."
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

variable "retry_join_wan" {
  description = "Consul retry_join_wan option for WAN federation."
  type        = list(string)
  default     = null
}

variable "primary_datacenter" {
  description = "Primary datacenter for the consul agent (required to match across datacenters for CA to work right with WAN fed)."
  type        = string
  default     = ""
}

variable "primary_gateways" {
  description = "Primary datacenter for the consul agent (required to match across datacenters for CA to work right with WAN fed)."
  type        = list(string)
  default     = null
}

variable "enable_mesh_gateway_wan_federation" {
  description = "Controls whether or not WAN federation via mesh gateways is enabled. Default is false."
  type        = bool
  default     = false
}