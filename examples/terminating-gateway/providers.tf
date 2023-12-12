terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.63.0"
    }
    consul = {
      source  = "hashicorp/consul"
      version = "2.20.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "consul" {
  alias      = "dc1-cluster"
  address    = "http://${module.dc1.dev_consul_server.lb_dns_name}:8500"
  datacenter = "dc1"
  token      = module.dc1.dev_consul_server.bootstrap_token_id
}