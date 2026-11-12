# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# ---------------------------------------------------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY
# AWS_DEFAULT_REGION

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These parameters have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
  default     = "consul-example"
}

variable "aws_region" {
  description = "What region the cluster and resources will be deployed into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "The ID of the existing VPC."
  type        = string
}

variable "private_subnet_ids" {
  description = "The existing VPC Private Subnets. Should be at least 3 and should match server count."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "The existing VPC Public Subnets. Should be at least 3 and should match server count."
  type        = list(string)
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
  default = "X86_64"
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

variable "lb_enabled" {
  description = "Whether to create an ALB for the server task. Useful for accessing the UI."
  type        = bool
  default     = true
}

variable "internal_alb_listener" {
  type        = bool
  description = "ALB is internal-only to reduce load-test costs. When false the ALB will be accessible over the public network."
  default     = true
}

variable "deploy_efs_cluster" {
  type        = bool
  description = "Deploy EFS Cluster for Consul data storage? Default is true."
  default     = true
}

variable "ecs_cluster_name" {
  description = "Specify an ECS cluster name to deploy the consul services."
  default     = null
}

variable "create_ecs_log_group" {
  description = "Create an ECS Log Group for the containers. Default is True"
  default     = true
}

variable "ecs_log_retention_period" {
  description = "Specify a log retnetion period in days. Default is 7."
  default     = 7
}

variable "consul_container_cpu" {
  description = "Set the Consul Container total CPU limit. Default is 2048."
  default     = 2048
}

variable "consul_container_memory" {
  description = "Set the Consul Cotainer total Memory limit. Default is 4096."
  default     = 4096
}

variable "consul_task_cpu" {
  description = "Set the Consul Server task CPU limit. Default is 1792."
  default     = 1792
}

variable "consul_task_memory" {
  description = "Set the Consul Server container Memory limit. Default is 3584."
  default     = 3584
}

variable "datadog_task_cpu" {
  description = "Set the Consul Server task CPU limit. Default is 1792."
  default     = 256
}

variable "datadog_task_memory" {
  description = "Set the Consul Server container Memory limit. Default is 3584."
  default     = 512
}

variable "aws_auto_join" {
  description = "Enable AWS Auto-Join based on ECS Tag value."
  default     = true
}

variable "raft_multiplier" {
  description = "The Consul Performance Raft-Multiplier. Default is 1."
  default     = 1
}

variable "run_k6" {
  type    = bool
  default = false
}

variable "k6_apikey" {
  description = "K6 API key"
  type        = string
  default     = ""
}

variable "datadog_apikey" {
  description = "Datadog API key"
  type        = string
  default     = ""
}

variable "lb_ingress_rule_cidr_blocks" {
  description = "CIDR blocks that are allowed access to the load balancer."
  type        = list(string)
  default     = null
}

variable "lb_ingress_rule_security_groups" {
  description = "Security groups that are allowed access to the load balancer."
  type        = list(string)
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

variable "service_discovery_namespace" {
  description = "The namespace where the Consul server service will be registered with AWS Cloud Map. Defaults to the Consul server domain name: server.<datacenter>.<domain>."
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "launch_type" {
  description = "Launch type on which to run service. Valid values are EC2 and FARGATE."
  type        = string
  default     = "EC2"
}

variable "assign_public_ip" {
  description = "Assign a public IP address to the ENI. If running in public subnets this is required so that ECS can pull the Docker images."
  type        = bool
  default     = false
}

variable "tls" {
  description = "Whether to enable TLS on the server for the control plane traffic."
  type        = bool
  default     = false
}

variable "generate_ca" {
  description = "Controls whether or not a CA key and certificate will automatically be created and stored in Secrets Manager. Default is true. Set this to false and set ca_cert_arn and ca_key_arn to provide pre-existing secrets."
  type        = bool
  default     = true
}

variable "ca_cert_arn" {
  description = "The Secrets Manager ARN of the Consul CA certificate."
  type        = string
  default     = ""
}

variable "ca_key_arn" {
  description = "The Secrets Manager ARN of the Consul CA certificate key."
  type        = string
  default     = ""
}

variable "gossip_encryption_enabled" {
  description = "Whether or not to enable gossip encryption."
  type        = bool
  default     = false
}

variable "generate_gossip_encryption_key" {
  description = "Controls whether or not a gossip encryption key will automatically be created and stored in Secrets Manager. Default is true. Set this to false and set gossip_key_secret_arn to provide a pre-existing secret."
  type        = bool
  default     = true
}

variable "gossip_key_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul gossip encryption key. A gossip encryption key will automatically be created and stored in Secrets Manager if gossip encryption is enabled and this variable is not provided."
  type        = string
  default     = ""
}

variable "acls" {
  description = "Whether to enable ACLs on the server."
  type        = bool
  default     = false
}

variable "generate_bootstrap_token" {
  description = "Whether to automatically generate a bootstrap token."
  type        = bool
  default     = true
}

variable "bootstrap_token" {
  description = "The Consul bootstrap token. By default a bootstrap token will be generated automatically. This field can be used to explicity set the value of the bootstrap token."
  type        = string
  default     = ""
}

variable "bootstrap_token_arn" {
  description = "The ARN of the Secrets Manager secret containing the Consul bootstrap token. By default a secret will be created automatically."
  type        = string
  default     = ""
}

variable "wait_for_steady_state" {
  description = "Set wait_for_steady_state on the ECS service. This causes Terraform to wait for the Consul server task to be deployed."
  type        = bool
  default     = false
}

variable "datacenter" {
  description = "Consul datacenter. Defaults to 'dc1'."
  type        = string
  default     = "dc1"
}

variable "node_name" {
  description = "Node name of the Consul server. Defaults to the value of 'var.name'."
  type        = string
  default     = ""
}

variable "primary_datacenter" {
  description = "Consul primary datacenter. Required when joining Consul datacenters via mesh gateways. All datacenters are required to use the same primary datacenter."
  type        = string
  default     = ""
}

variable "retry_join_wan" {
  description = "List of WAN addresses to join for Consul cluster peering. Must not be provided when using mesh-gateway WAN federation."
  type        = list(string)
  default     = []
}

variable "primary_gateways" {
  description = "List of WAN addresses of the primary mesh gateways for Consul servers in secondary datacenters to use to reach the Consul servers in the primary datcenter."
  type        = list(string)
  default     = []
}

variable "enable_mesh_gateway_wan_federation" {
  description = "Controls whether or not WAN cluster peering via mesh gateways is enabled. Default is false."
  type        = bool
  default     = false
}

variable "additional_dns_names" {
  description = "List of additional DNS names to add to the Subject Alternative Name (SAN) field of the server's certificate."
  type        = list(string)
  default     = []
}

variable "replication_token" {
  description = "Replication token required for ACL replication in secondary datacenters. See https://www.consul.io/docs/security/acl/acl-federated-datacenters."
  type        = string
  default     = ""
}

locals {
  retry_join_wan_xor_primary_gateways = length(var.retry_join_wan) > 0 && length(var.primary_gateways) > 0 ? file("ERROR: Only one of retry_join_wan or primary_gateways may be provided.") : null
}
