variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
  default     = "consul-ecs"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "lb_ingress_ip" {
  description = "Your IP. This is used in the load balancer security groups to ensure only you can access the Consul UI and example application."
  type        = string
}

variable "public_ssh_key" {
  description = "Local file path of a public ssh key. If specified, a bastion server (jump host) is created on order to login to container instances."
  type        = string
  default     = null
}
