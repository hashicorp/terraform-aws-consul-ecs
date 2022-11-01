variable "name" {
  default = "k6Lambda"
}

variable "vpc_id" {
  type = string
}

variable "subnets" {
  type = list(string)
}

variable "apikey" {
  default = ""
}

variable "target" {
  type = string
}

variable "k6_version" {
  description = "Release Tag. https://github.com/grafana/k6/releases"
  type        = string
  default     = "v0.41.0"
}