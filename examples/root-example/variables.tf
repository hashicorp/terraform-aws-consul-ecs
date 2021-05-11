variable "ecs_cluster" {
  description = "Name of pre-existing ECS cluster"
}

variable "dev_server_enabled" {
  type        = bool
  default     = true
  description = "Whether the Consul dev server running on ECS is enabled"
}

variable "region" {}

variable "consul_image" {
  default = "docker.io/hashicorp/consul:1.9.4"
}

variable "consul_ecs_image" {}

variable "envoy_image" {
  default = "docker.io/envoyproxy/envoy-alpine:v1.16.2"
}

variable "vpc_id" {}

variable "tags" {}

variable "subnets" {}
variable "lb_subnets" {}

# Description for the ingress rule in front of the Server and Client mesh app's
# loadbalancer.
variable "lb_ingress_security_group_rule_description" {}

# CIDR blocks for the ingress rule in front of the Server and Client mesh app's
# loadbalancer. Used to restrict outside access to the Consul server's UI.
variable "lb_ingress_security_group_rule_cidr_blocks" {}

variable "log_group_name" {}
variable "mesh_client_app_lb_name" {
  default = "mesh-client"
}
