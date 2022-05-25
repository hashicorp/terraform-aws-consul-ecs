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
  description = "Consul retry_join_wan option for WAN cluster peering."
  type        = list(string)
  default     = []
}

variable "primary_datacenter" {
  description = "Primary datacenter for the consul agent (required to match across datacenters for CA to work right with WAN fed)."
  type        = string
  default     = ""
}

variable "primary_gateways" {
  description = "Primary datacenter for the consul agent (required to match across datacenters for CA to work right with WAN fed)."
  type        = list(string)
  default     = []
}

variable "enable_mesh_gateway_wan_peering" {
  description = "Controls whether or not WAN cluster peering via mesh gateways is enabled. Default is false."
  type        = bool
  default     = false
}

variable "ca_cert_arn" {
  description = "The Secrets Manager ARN of the Consul CA certificate. A CA certificate will automatically be created and stored in Secrets Manager if TLS is enabled and this variable is not provided."
  type        = string
  default     = ""
}

variable "ca_key_arn" {
  description = "The Secrets Manager ARN of the Consul CA certificate key. A CA certificate key will automatically be created and stored in Secrets Manager if TLS is enabled and this variable is not provided."
  type        = string
  default     = ""
}

variable "gossip_key_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul gossip encryption key. A gossip encryption key will be generated if gossip encryption is enabled and this is not provided."
  type        = string
  default     = ""
}

variable "additional_dns_names" {
  type    = list(string)
  default = []
}

variable "node_name" {
  type    = string
  default = ""
}
