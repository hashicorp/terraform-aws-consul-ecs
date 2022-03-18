variable "region" {
  type        = string
  description = "Region."
}

variable "vpc_id" {
  description = "The ID of the VPC for all resources."
  type        = string
}

variable "route_table_ids" {
  description = "IDs of the route tables for peering with HVN."
  type        = list(string)
}

variable "suffix" {
  type        = string
  default     = ""
  description = "Suffix to add to all resource names."
}
