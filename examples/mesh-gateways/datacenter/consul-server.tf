# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

# Run the Consul dev server as an ECS task.
module "dev_consul_server" {
  name                        = "${var.name}-consul-server"
  source                      = "../../../modules/dev-server"
  datacenter                  = var.datacenter
  primary_datacenter          = var.primary_datacenter
  retry_join_wan              = var.retry_join_wan
  primary_gateways            = var.primary_gateways
  ecs_cluster_arn             = aws_ecs_cluster.this.arn
  subnet_ids                  = var.private_subnets
  vpc_id                      = var.vpc.vpc_id
  lb_enabled                  = true
  lb_subnets                  = var.public_subnets
  lb_ingress_rule_cidr_blocks = ["${var.lb_ingress_ip}/32"]
  tls                         = true
  generate_ca                 = false
  ca_cert_arn                 = var.ca_cert_arn
  ca_key_arn                  = var.ca_key_arn
  acls                        = true
  bootstrap_token             = var.bootstrap_token
  bootstrap_token_arn         = var.bootstrap_token_arn
  generate_bootstrap_token    = false
  replication_token           = var.replication_token
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-server"
    }
  }
  launch_type = "FARGATE"

  enable_mesh_gateway_wan_federation = var.enable_mesh_gateway_wan_federation
  consul_server_startup_timeout      = var.consul_server_startup_timeout
}

resource "aws_security_group_rule" "consul_server_ingress" {
  description              = "Access to Consul dev server from default security group"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = var.vpc.default_security_group_id
  security_group_id        = module.dev_consul_server.security_group_id
}
