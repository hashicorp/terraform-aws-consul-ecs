variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
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
