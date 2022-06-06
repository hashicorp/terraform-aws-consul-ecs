variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
}

variable "consul_image" {
  description = "The Consul image to use. Should be enterprise for HCP servers."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul-enterprise:1.12.0-ent"
}

variable "datacenter_names" {
  description = "Names of Consul datacenters to use."
  type        = list(string)
  default     = ["dc1", "dc2"]

  validation {
    error_message = "Exactly two datacenter names are required."
    condition     = length(var.datacenter_names) == 2
  }
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
