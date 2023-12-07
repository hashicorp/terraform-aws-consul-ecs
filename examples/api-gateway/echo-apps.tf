# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module "echo-app-1" {
  source              = "./echo-service"
  name                = "one"
  region              = var.region
  ecs_cluster_arn     = aws_ecs_cluster.this.arn
  private_subnets     = module.vpc.private_subnets
  consul_server_hosts = module.dc1.dev_consul_server.server_dns
  consul_ca_cert_arn  = module.dc1.dev_consul_server.ca_cert_arn
  log_group_name      = aws_cloudwatch_log_group.log_group.name
}

module "echo-app-2" {
  source              = "./echo-service"
  name                = "two"
  region              = var.region
  ecs_cluster_arn     = aws_ecs_cluster.this.arn
  private_subnets     = module.vpc.private_subnets
  consul_server_hosts = module.dc1.dev_consul_server.server_dns
  consul_ca_cert_arn  = module.dc1.dev_consul_server.ca_cert_arn
  log_group_name      = aws_cloudwatch_log_group.log_group.name
}

// Intention to allow traffic from the API gateway to the echo app one
resource "consul_config_entry" "gateway_echo_app_one_intention" {
  kind     = "service-intentions"
  name     = module.echo-app-1.name
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Sources = [
      {
        Name       = "${var.name}-api-gateway"
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      }
    ]
  })
}

// Intention to allow traffic from the API gateway to the echo app one
resource "consul_config_entry" "gateway_echo_app_two_intention" {
  kind     = "service-intentions"
  name     = module.echo-app-2.name
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Sources = [
      {
        Name       = "${var.name}-api-gateway"
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      }
    ]
  })
}

// Service defaults for echo app one
resource "consul_config_entry" "echo_app_one_defaults" {
  kind     = "service-defaults"
  name     = module.echo-app-1.name
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Protocol = "http"
  })
}

// Service defaults for echo app one
resource "consul_config_entry" "echo_app_two_defaults" {
  kind     = "service-defaults"
  name     = module.echo-app-2.name
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Protocol = "http"
  })
}

// API gateway http route information for echo services
resource "consul_config_entry" "api_gw_http_route_echo" {
  depends_on = [consul_config_entry.echo_app_one_defaults, consul_config_entry.echo_app_two_defaults, consul_config_entry.api_gateway_entry]

  name = "${var.name}-echo-http-route"
  kind = "http-route"

  config_json = jsonencode({
    Rules = [
      {
        Matches = [
          {
            Path = {
              Match = "exact"
              Value = "/echo"
            }
          }
        ]
        Services = [
          {
            Name   = module.echo-app-1.name
            Weight = 50
          },
          {
            Name   = module.echo-app-2.name
            Weight = 50
          }
        ]
      }
    ]

    Parents = [
      {
        Kind        = "api-gateway"
        Name        = "${var.name}-api-gateway"
        SectionName = "api-gw-http-listener"
      }
    ]
  })

  provider = consul.dc1-cluster
}