# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.73.0"
    }
    consul = {
      source  = "hashicorp/consul"
      version = "2.18.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.1.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.3.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "3.4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "consul" {
  alias      = "consul-cluster"
  address    = "http://${module.dev_consul_server.lb_dns_name}:8500"
  datacenter = "dc1"
  token      = module.dev_consul_server.bootstrap_token_id
}