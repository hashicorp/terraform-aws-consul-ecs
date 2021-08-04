variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
}

variable "vpc_id" {
  description = "The VPC for the EC2 instance."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the EC2 instance."
  type        = string
}

variable "ingress_ip" {
  description = "Your IP. This is used in security groups to ensure only you can access the server."
  type        = string
}

variable "public_ssh_key" {
  description = "Local file path of a public ssh key to login to the bastion server."
  type        = string
}

variable "destination_security_group" {
  description = "Used to create a rule to allow SSH from the bastion to container instances."
  type        = string
}
