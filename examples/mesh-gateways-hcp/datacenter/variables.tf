variable "name" {
  description = "Name to be used on all the resources as identifier."
  type        = string
}

variable "datacenter" {
  description = "Name of the consul datacenter."
  type        = string
}

variable "hvn_cidr_block" {
  description = "CIDR block for the HVN"
  type        = string

}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "is_secondary" {
  description = "If true, this is a secondary datacenter. When this is true, the hcp_primary_link must be provided."
  type        = bool
  default     = false
}

variable "hcp_primary_link" {
  description = "The self_link of the hcp_consul_cluster in the primary datacenter. This configures this datacenter as a secondary, federated with the primary."
  type        = string
  default     = ""
}

variable "vpc" {
  description = "VPC object from terraform-aws-modules/vpc/aws module."
  type = object({
    default_security_group_id = string
    private_subnets           = list(string)
    private_route_table_ids   = list(string)
    public_subnets            = list(string)
    public_route_table_ids    = list(string)
    vpc_cidr_block            = string
    vpc_id                    = string
  })
}
