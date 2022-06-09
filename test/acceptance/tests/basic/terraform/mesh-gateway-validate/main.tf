provider "aws" {
  region = "us-west-2"
}

variable "kind" {
  type = string
}

variable "consul_namespace" {
  type = string
}

variable "retry_join_wan" {
  type = list(string)
}

variable "enable_mesh_gateway_wan_federation" {
  type = bool
}

variable "tls" {
  type = bool
}

module "test_gateway" {
  source                             = "../../../../../../modules/gateway-task"
  family                             = "family"
  kind                               = var.kind
  consul_namespace                   = var.consul_namespace
  retry_join                         = ["localhost:8500"]
  retry_join_wan                     = var.retry_join_wan
  enable_mesh_gateway_wan_federation = var.enable_mesh_gateway_wan_federation
  tls                                = var.tls
}
