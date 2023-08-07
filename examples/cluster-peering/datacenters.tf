# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  datacenter_1 = var.datacenter_names[0]
  datacenter_2 = var.datacenter_names[1]
}

module "dc1" {
  source = "./datacenter"

  name            = "${var.name}-${local.datacenter_1}"
  datacenter      = local.datacenter_1
  lb_ingress_ip   = var.lb_ingress_ip
  private_subnets = module.dc1_vpc.private_subnets
  public_subnets  = module.dc1_vpc.public_subnets
  region          = var.region
  vpc             = module.dc1_vpc

  consul_ecs_image = var.consul_ecs_image
}

module "dc2" {
  source = "./datacenter"

  name            = "${var.name}-${local.datacenter_2}"
  datacenter      = local.datacenter_2
  lb_ingress_ip   = var.lb_ingress_ip
  private_subnets = module.dc2_vpc.private_subnets
  public_subnets  = module.dc2_vpc.public_subnets
  region          = var.region
  vpc             = module.dc2_vpc

  consul_ecs_image = var.consul_ecs_image
}

// Create a null_resource that will wait for the Consul server to be available via its ALB.
// This allows us to wait until the Consul server is reachable before trying to create
// Consul resources like config entries. If we don't wait, Terraform will fail to create
// the necessary Consul resources.
resource "null_resource" "wait_for_dc1_consul_server" {
  depends_on = [module.dc1]
  triggers = {
    // Trigger update when Consul server ALB DNS name changes.
    consul_server_lb_dns_name = "${module.dc1.dev_consul_server.lb_dns_name}"
  }
  provisioner "local-exec" {
    command = <<EOT
stopTime=$(($(date +%s) + ${var.consul_server_startup_timeout})) ; \
while [ $(date +%s) -lt $stopTime ] ; do \
  sleep 10 ; \
  statusCode=$(curl -s -o /dev/null -w '%%{http_code}' http://${module.dc1.dev_consul_server.lb_dns_name}:8500/v1/catalog/services)
  [ $statusCode -eq 200 ] && break; \
done
EOT
  }
}

resource "null_resource" "wait_for_dc2_consul_server" {
  depends_on = [module.dc2]
  triggers = {
    // Trigger update when Consul server ALB DNS name changes.
    consul_server_lb_dns_name = "${module.dc2.dev_consul_server.lb_dns_name}"
  }
  provisioner "local-exec" {
    command = <<EOT
stopTime=$(($(date +%s) + ${var.consul_server_startup_timeout})) ; \
while [ $(date +%s) -lt $stopTime ] ; do \
  sleep 10 ; \
  statusCode=$(curl -s -o /dev/null -w '%%{http_code}' http://${module.dc2.dev_consul_server.lb_dns_name}:8500/v1/catalog/services)
  [ $statusCode -eq 200 ] && break; \
done
EOT
  }
}

resource "consul_config_entry" "mesh_dc1" {
  depends_on = [null_resource.wait_for_dc1_consul_server]

  kind     = "mesh"
  name     = "mesh"
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Peering = {
      PeerThroughMeshGateways = true
    }
  })
}

resource "consul_config_entry" "mesh_dc2" {
  depends_on = [null_resource.wait_for_dc2_consul_server]

  kind     = "mesh"
  name     = "mesh"
  provider = consul.dc2-cluster

  config_json = jsonencode({
    Peering = {
      PeerThroughMeshGateways = true
    }
  })
}

# We must wait for the mesh gateways belonging to both the datacenters to
# become healthy before initiating peering between them. We solely rely
# on the /v1/health/check/:service API to identify the readiness.
# We also add a custom sleep for around a minute to make sure to avoid
# any race conditions that might prevent traffic from flowing through
# the gateways.
resource "null_resource" "wait_for_mesh_gateway_dc1" {
  depends_on = [null_resource.wait_for_dc1_consul_server]

  provisioner "local-exec" {
    command = <<EOT
stopTime=$(($(date +%s) + ${var.mesh_gateway_readiness_timeout})) ; \
while [ $(date +%s) -lt $stopTime ] ; do \
  sleep 10 ; \
  meshGatewayStatus=$(curl http://${module.dc1.dev_consul_server.lb_dns_name}:8500/v1/health/checks/${local.mgw_name_1} | jq -r ".[0].Status")
  [ "$meshGatewayStatus" = passing ] && break; \
done ; \
sleep 60
EOT
  }
}

resource "null_resource" "wait_for_mesh_gateway_dc2" {
  depends_on = [null_resource.wait_for_dc2_consul_server]

  provisioner "local-exec" {
    command = <<EOT
stopTime=$(($(date +%s) + ${var.mesh_gateway_readiness_timeout})) ; \
while [ $(date +%s) -lt $stopTime ] ; do \
  sleep 10 ; \
  meshGatewayStatus=$(curl http://${module.dc2.dev_consul_server.lb_dns_name}:8500/v1/health/checks/${local.mgw_name_2} | jq -r ".[0].Status")
  [ "$meshGatewayStatus" = passing ] && break; \
done ; \
sleep 60
EOT
  }
}

resource "consul_peering_token" "this" {
  depends_on = [null_resource.wait_for_mesh_gateway_dc1, null_resource.wait_for_mesh_gateway_dc2]
  provider   = consul.dc2-cluster
  peer_name  = "dc1-cluster"
}

resource "consul_peering" "dc1-dc2" {
  provider = consul.dc1-cluster

  peer_name     = "${local.datacenter_1}-cluster"
  peering_token = consul_peering_token.this.peering_token
}

# Exported service config server to make the server app
# available to the client app present in the peer datacenter
resource "consul_config_entry" "export_peer_service" {
  depends_on = [consul_peering.dc1-dc2]

  kind     = "exported-services"
  name     = "default"
  provider = consul.dc2-cluster

  config_json = jsonencode({
    Name = "default"
    Services = [
      {
        Name = local.example_server_app_name
        Consumers = [
          {
            Peer = "${local.datacenter_2}-cluster"
          }
        ]
      }
    ]
  })
}

// Intention to allow traffic from the client app present
// in the peer datacenter.
resource "consul_config_entry" "service_intention" {
  kind     = "service-intentions"
  name     = local.example_server_app_name
  provider = consul.dc2-cluster

  config_json = jsonencode({
    Sources = [
      {
        Name       = local.example_client_app_name
        Peer       = "${local.datacenter_1}-cluster"
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      }
    ]
  })
  depends_on = [null_resource.wait_for_dc2_consul_server]
}

// Our app tasks need to allow ingress from the dev-server (in the relevant dc).
// The apps use the default security group so we allow ingress to default from both dev-servers.
resource "aws_security_group_rule" "default_ingress_from_dc1" {
  description              = "Access from dev-server in dc1"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.dc1.dev_consul_server.security_group_id
  security_group_id        = module.dc1_vpc.default_security_group_id
}

resource "aws_security_group_rule" "default_ingress_from_dc2" {
  description              = "Access from dev-server in dc2"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.dc2.dev_consul_server.security_group_id
  security_group_id        = module.dc2_vpc.default_security_group_id
}
