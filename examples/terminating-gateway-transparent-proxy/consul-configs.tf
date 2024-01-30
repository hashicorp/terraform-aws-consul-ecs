# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

resource "consul_service" "external_server_service" {
  depends_on = [module.dc1]
  name       = "${var.name}-external-server-app"
  node       = consul_node.external_node.name
  port       = 9090
  provider   = consul.dc1-cluster
}

resource "consul_node" "external_node" {
  depends_on = [module.dc1]
  name       = "${var.name}_external_server_app_node"
  address    = aws_lb.example_server_app.dns_name
  meta = {
    "external-node" = "true"
  }
  provider = consul.dc1-cluster
}

resource "consul_config_entry" "mesh_cfg_entry" {
  depends_on = [module.dc1]
  name       = "mesh"
  kind       = "mesh"

  config_json = jsonencode({
    TransparentProxy = {
      MeshDestinationsOnly = true
    }
  })

  provider = consul.dc1-cluster
}

resource "consul_config_entry" "external_service_intentions" {
  depends_on = [module.dc1]
  name       = "${var.name}-external-server-app"
  kind       = "service-intentions"

  config_json = jsonencode({
    Sources = [
      {
        Name   = "${var.name}-example-client-app"
        Action = "allow"
      }
    ]
  })

  provider = consul.dc1-cluster
}

resource "consul_config_entry" "terminating_gateway_entry" {
  depends_on = [module.dc1]

  name = "${var.name}-terminating-gateway"
  kind = "terminating-gateway"

  config_json = jsonencode({
    Services = [{ Name = "${var.name}-external-server-app" }]
  })

  provider = consul.dc1-cluster
}

resource "consul_acl_policy" "external_server_app_policy" {
  depends_on = [module.dc1]

  name  = "external_server_app_write_policy"
  rules = <<-RULE
    service "${var.name}-external-server-app" {
      policy = "write"
    }
    RULE

  provider = consul.dc1-cluster
}

# A null_resource to introduce an arbitrary delay. This is
# done to make sure that the ECS controller has already
# created the required consul-ecs-terminating-gateway-role.
# Sleeping for 60 seconds might not all be needed but
# it is just added to completely ensure that the role is present
# in Consul.
resource "null_resource" "arbitrary_delay" {
  depends_on = [module.ecs_controller]
  triggers = {
    force_recreate = timestamp()
  }

  provisioner "local-exec" {
    command = "sleep 60"
  }
}

data "consul_acl_role" "ecs_terminating_gateway_default_role" {
  depends_on = [null_resource.arbitrary_delay]
  name       = "consul-ecs-terminating-gateway-role"

  provider = consul.dc1-cluster
}

resource "consul_acl_role_policy_attachment" "external_server_app_role_policy_attachment" {
  role_id = data.consul_acl_role.ecs_terminating_gateway_default_role.id
  policy  = consul_acl_policy.external_server_app_policy.name

  provider = consul.dc1-cluster
}