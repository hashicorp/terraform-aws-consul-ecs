variable "region" {
  default     = "us-west-2"
  description = "AWS region"
}

variable "role_arn" {
  default     = ""
  description = "AWS role for the AWS provider to assume when running these templates."
}

variable "tags" {
  type        = map(any)
  default     = {}
  description = "Tags to attach to the created resources."
}

variable "instance_count" {
  description = "Number of EC2 instances to create for ECS cluster capacity."
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "The instance type for EC2 instances."
  type        = string
  default     = "t3a.micro"
}
