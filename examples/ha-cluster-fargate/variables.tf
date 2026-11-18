variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
  default     = "consul-dc1"
}

variable "vpc_az" {
  type        = list(string)
  description = "VPC Availability Zone"
  validation {
    condition     = length(var.vpc_az) >= 2
    error_message = "VPC needs at least two Availability Zones for ALB to work."
  }
  default = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

variable "vpc_name" {
  description = "Name of the VPC"
  default     = "consul-vpc"
}

variable "vpc_cidr" {
  description = "List of CIDR blocks for the VPC module"
  default     = "10.0.0.0/16"
}

variable "vpc_allowed_ssh_cidr" {
  description = "List of CIDR blocks allowed to ssh to the test server; set to 0.0.0.0/0 to allow access from anywhere"
  default     = "10.0.0.0/16"
}

variable "lb_ingress_rule_cidr_blocks" {
  description = "CIDR blocks that are allowed access to the load balancer."
  type        = list(string)
  default     = []
}

variable "lb_ingress_rule_security_groups" {
  description = "Security groups that are allowed access to the load balancer."
  type        = list(string)
  default     = []
}

variable "single_nat_gateway" {
  description = "Deploy a single nat gateway. Default is false."
  default     = true
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR Block for the Public Subnet, must be within VPC CIDR range"
  default     = ["10.0.1.0/24", "10.0.3.0/24", "10.0.5.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR Block for the Private Subnet, must be within VPC CIDR range"
  default     = ["10.0.2.0/24", "10.0.4.0/24", "10.0.6.0/24"]
}

variable "consul_image" {
  type        = string
  description = "Name of the Consul Agent Docker Image"
  default     = "public.ecr.aws/hashicorp/consul:1.12.2"
}

variable "operating_system_family" {
  default = "LINUX"
}

variable "cpu_architecture" {
  default = "ARM64"
}

variable "docker_username" {
  type        = string
  description = "Username for Docker Hub authentication."
  default     = null
}

variable "docker_password" {
  type        = string
  description = "Password (or token) for Docker Hub authentication."
  default     = null
}

variable "consul_count" {
  description = "Number of consul servers to deploy. Default 3"
  default     = 3
}

variable "consul_license" {
  description = "A Consul Enterprise license key. Requires consul_image to be set to a Consul Enterprise image."
  type        = string
  default     = ""
  sensitive   = true
}

variable "invoke_loadtest" {
  default = false
}
