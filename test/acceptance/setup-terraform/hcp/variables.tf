variable "region" {
  description = "AWS region"
  type        = string
}

variable "suffix" {
  description = "Suffix to append to resource names."
  type        = string
}

variable "vpc" {
  description = "VPC object from terraform-aws-modules/vpc/aws module."
  type        = any
}

