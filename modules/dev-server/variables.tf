variable "tags" {}
variable "ecs_cluster_arn" {}
variable "subnets" {
  type = list(string)
}
variable "load_balancer_enabled" {
  default = false
  type    = bool
}
variable "vpc_id" {
  type    = string
  default = ""
}
variable "lb_subnets" {
  type    = list(string)
  default = []
}
variable "lb_ingress_description" {
  type    = string
  default = ""
}
variable "lb_ingress_cidr_blocks" {
  type    = list(string)
  default = []
}
variable "consul_image" {
  type    = string
  default = "hashicorp/consul:1.9.5"
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
  default     = "consul-server"
}
