variable "consul_ecs_image" {
  description = "consul-ecs Docker image."
  type        = string
  default     = "public.ecr.aws/hashicorp/consul-ecs:0.4.1"
}

variable "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster where the controller will be running."
  type        = string
}

variable "region" {
  description = "AWS region of the ECS cluster."
  type        = string
}

variable "requires_compatibilities" {
  description = "Set of launch types required by the task."
  type        = list(string)
  default     = ["EC2", "FARGATE"]
}

variable "launch_type" {
  description = "Launch type on which to run service. Valid values are EC2 and FARGATE."
  type        = string
  default     = "FARGATE"
}

variable "consul_bootstrap_token_secret_arn" {
  description = "The ARN of the AWS SecretsManager secret containing the token to be used by this controller. The token needs to have at least `acl:write` privileges in Consul."
  type        = string
}

variable "log_configuration" {
  description = "Task definition log configuration object (https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html)."
  type        = any
  default     = null
}

variable "iam_role_path" {
  description = "IAM roles at this path will be permitted to login to the Consul AWS IAM auth method configured by this controller."
  type        = string
  default     = ""
}

variable "subnets" {
  description = "Subnets where the controller task should be deployed. If these are private subnets then there must be a NAT gateway for image pulls to work. If these are public subnets then you must also set assign_public_ip for image pulls to work."
  type        = list(string)
}

variable "consul_server_http_addr" {
  description = "The HTTP(S) address of the Consul server. This must be a full URL, including port and scheme, e.g. https://consul.example.com:8501."
  type        = string
}

variable "name_prefix" {
  description = "The prefix that will be used for all resources created by this module, including AWS Secrets. Must be non-empty."
  type        = string
}

variable "consul_server_ca_cert_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul server CA certificate."
  type        = string
  default     = ""
}

variable "assign_public_ip" {
  description = "Configure the ECS Service to assign a public IP to the task. This is required if running tasks on a public subnet."
  type        = bool
  default     = false
}

variable "consul_partitions_enabled" {
  description = "Enable admin partitions [Consul Enterprise]."
  type        = bool
  default     = false
}

variable "consul_partition" {
  description = "Admin partition the controller will manage [Consul Enterprise]."
  type        = string
  default     = "default"
}

variable "security_groups" {
  description = "Configure the ECS service with security groups. If not specified, the default security group for the VPC is used."
  type        = list(string)
  default     = []
}
