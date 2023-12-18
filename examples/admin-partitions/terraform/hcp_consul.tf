# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

terraform {
  required_providers {
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.66.0"
    }
  }
}

// Configure the provider
provider "hcp" {
  project_id = var.hcp_project_id
}

locals {
  server_host = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["retry_join"][0]
}

// Create HCP Consul resources.
resource "hcp_hvn" "server" {
  hvn_id         = "hvn-${local.rand_suffix}"
  cloud_provider = "aws"
  region         = var.region
  cidr_block     = "172.25.16.0/20"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "selected" {
  id = module.vpc.vpc_id
}

resource "hcp_aws_network_peering" "this" {
  peering_id      = "${hcp_hvn.server.hvn_id}-peering"
  hvn_id          = hcp_hvn.server.hvn_id
  peer_vpc_id     = module.vpc.vpc_id
  peer_account_id = data.aws_caller_identity.current.account_id
  peer_vpc_region = var.region
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  vpc_peering_connection_id = hcp_aws_network_peering.this.provider_peering_id
  auto_accept               = true
}

resource "hcp_hvn_route" "peering_route" {
  depends_on       = [aws_vpc_peering_connection_accepter.peer]
  hvn_link         = hcp_hvn.server.self_link
  hvn_route_id     = "${hcp_hvn.server.hvn_id}-peering-route"
  destination_cidr = data.aws_vpc.selected.cidr_block
  target_link      = hcp_aws_network_peering.this.self_link
}

resource "aws_route" "peering" {
  count                     = length([module.vpc.public_route_table_ids[0], module.vpc.private_route_table_ids[0]])
  route_table_id            = [module.vpc.public_route_table_ids[0], module.vpc.private_route_table_ids[0]][count.index]
  destination_cidr_block    = hcp_hvn.server.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.peer.vpc_peering_connection_id
}

resource "hcp_consul_cluster" "this" {
  cluster_id         = "server-${local.rand_suffix}"
  datacenter         = "dc1"
  hvn_id             = hcp_hvn.server.hvn_id
  tier               = "development"
  public_endpoint    = true
  min_consul_version = "1.17.0"
}

// Configure Consul resources to allow cross-partition and cross-namespace communication.
provider "consul" {
  address    = hcp_consul_cluster.this.consul_public_endpoint_url
  datacenter = "dc1"
  token      = hcp_consul_cluster.this.consul_root_token_secret_id
}

// Create Admin Partition and Namespace for the client
resource "consul_admin_partition" "part1" {
  name        = var.client_partition
  description = "Partition for client service"
}

resource "consul_namespace" "ns1" {
  name        = var.client_namespace
  description = "Namespace for client service"
  partition   = consul_admin_partition.part1.name
}

// Create Admin Partition and Namespace for the server
resource "consul_admin_partition" "part2" {
  name        = var.server_partition
  description = "Partition for server service"
}

resource "consul_namespace" "ns2" {
  name        = var.server_namespace
  description = "Namespace for server service"
  partition   = consul_admin_partition.part2.name
}

// Create exported-services config entry to export the server to the client
resource "consul_config_entry" "exported_services" {
  kind = "exported-services"
  name = consul_admin_partition.part2.name

  config_json = jsonencode({
    Partition = consul_admin_partition.part2.name
    Services = [{
      Name      = "example_server_${local.server_suffix}"
      Partition = consul_admin_partition.part2.name
      Namespace = consul_namespace.ns2.name
      Consumers = [{
        Partition = consul_admin_partition.part1.name
      }]
    }]
  })
}

// Create an intention to allow the client to call the server
resource "consul_config_entry" "service_intentions" {
  kind      = "service-intentions"
  name      = "example_server_${local.server_suffix}"
  partition = consul_admin_partition.part2.name
  namespace = consul_namespace.ns2.name

  config_json = jsonencode({
    Partition = consul_admin_partition.part2.name
    Sources = [
      {
        Name       = "example_client_${local.client_suffix}"
        Partition  = consul_admin_partition.part1.name
        Namespace  = consul_namespace.ns1.name
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      }
    ]
  })
}

// Create AWS Secrets Manager secrets required by the mesh-tasks and ACL controllers
resource "aws_secretsmanager_secret" "bootstrap_token" {
  name = "${local.rand_suffix}-bootstrap-token"
}

resource "aws_secretsmanager_secret_version" "bootstrap_token" {
  secret_id     = aws_secretsmanager_secret.bootstrap_token.id
  secret_string = hcp_consul_cluster.this.consul_root_token_secret_id
}

resource "aws_secretsmanager_secret" "consul_ca_cert" {
  name = "${local.rand_suffix}-consul-ca-cert"
}

resource "aws_secretsmanager_secret_version" "consul_ca_cert" {
  secret_id     = aws_secretsmanager_secret.consul_ca_cert.id
  secret_string = base64decode(hcp_consul_cluster.this.consul_ca_file)
}
