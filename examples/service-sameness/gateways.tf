# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

locals {
  mgw_name_1 = "${var.name}-${local.datacenter_1}-default-mesh-gateway"
  mgw_name_2 = "${var.name}-${local.datacenter_1}-${var.dc1_consul_admin_partition}-mesh-gateway"
  mgw_name_3 = "${var.name}-${local.datacenter_2}-mesh-gateway"
}

module "dc1_gateway_default_partition" {
  source          = "./gateway"
  name            = local.mgw_name_1
  region          = var.region
  vpc             = module.dc1_vpc
  private_subnets = module.dc1_vpc.private_subnets
  public_subnets  = module.dc1_vpc.public_subnets
  cluster         = module.cluster1.ecs_cluster.arn
  log_group_name  = module.cluster1.log_group.name

  consul_ecs_image              = var.consul_ecs_image
  ca_cert_arn                   = module.dc1.dev_consul_server.ca_cert_arn
  consul_server_address         = module.dc1.dev_consul_server.server_dns
  consul_server_lb_dns_name     = module.dc1.dev_consul_server.lb_dns_name
  consul_server_bootstrap_token = module.dc1.dev_consul_server.bootstrap_token_id

  mesh_gateway_readiness_timeout = var.mesh_gateway_readiness_timeout
  additional_task_role_policies  = [aws_iam_policy.execute_command.arn]
}

module "dc1_gateway_part1_partition" {
  depends_on = [module.ecs_controller_dc1_part1_partition]

  source          = "./gateway"
  name            = local.mgw_name_2
  region          = var.region
  vpc             = module.dc1_vpc
  private_subnets = module.dc1_vpc.private_subnets
  public_subnets  = module.dc1_vpc.public_subnets
  cluster         = module.cluster2.ecs_cluster.arn
  log_group_name  = module.cluster2.log_group.name

  consul_ecs_image              = var.consul_ecs_image
  ca_cert_arn                   = module.dc1.dev_consul_server.ca_cert_arn
  consul_server_address         = module.dc1.dev_consul_server.server_dns
  consul_server_lb_dns_name     = module.dc1.dev_consul_server.lb_dns_name
  consul_server_bootstrap_token = module.dc1.dev_consul_server.bootstrap_token_id
  consul_partition              = var.dc1_consul_admin_partition

  mesh_gateway_readiness_timeout = var.mesh_gateway_readiness_timeout
  additional_task_role_policies  = [aws_iam_policy.execute_command.arn]
}


// DC2 gateway
module "dc2_gateway" {
  source          = "./gateway"
  name            = local.mgw_name_3
  region          = var.region
  vpc             = module.dc2_vpc
  private_subnets = module.dc2_vpc.private_subnets
  public_subnets  = module.dc2_vpc.public_subnets
  cluster         = module.cluster3.ecs_cluster.arn
  log_group_name  = module.cluster3.log_group.name

  consul_ecs_image              = var.consul_ecs_image
  ca_cert_arn                   = module.dc2.dev_consul_server.ca_cert_arn
  consul_server_address         = module.dc2.dev_consul_server.server_dns
  consul_server_lb_dns_name     = module.dc2.dev_consul_server.lb_dns_name
  consul_server_bootstrap_token = module.dc2.dev_consul_server.bootstrap_token_id

  mesh_gateway_readiness_timeout = var.mesh_gateway_readiness_timeout
  additional_task_role_policies  = [aws_iam_policy.execute_command.arn]
}

// Policy that allows execution of remote commands in ECS tasks.
resource "aws_iam_policy" "execute_command" {
  name   = "${var.name}-ecs-execute-command"
  path   = "/"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF

}
