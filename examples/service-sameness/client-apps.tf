# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module "client_app_dc1" {
  datacenter      = local.datacenter_1
  source          = "./client-app"
  name            = var.name
  region          = var.region
  ecs_cluster_arn = module.cluster1.ecs_cluster.arn
  log_group_name  = module.cluster1.log_group.name
  port            = "9090"

  vpc_id                        = module.dc1_vpc.vpc_id
  vpc_default_security_group_id = module.dc1_vpc.default_security_group_id
  private_subnets               = module.dc1.private_subnets
  public_subnets                = module.dc1.public_subnets

  consul_server_address              = module.dc1.dev_consul_server.server_dns
  consul_server_ca_cert_arn          = module.dc1.dev_consul_server.ca_cert_arn
  consul_server_lb_security_group_id = module.dc1.dev_consul_server.lb_security_group_id
  consul_ecs_image                   = var.consul_ecs_image

  lb_ingress_ip                 = var.lb_ingress_ip
  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
}

module "client_app_dc1_part1" {
  depends_on      = [module.ecs_controller_dc1_part1_partition]
  datacenter      = local.datacenter_1
  source          = "./client-app"
  name            = var.name
  region          = var.region
  ecs_cluster_arn = module.cluster2.ecs_cluster.arn
  log_group_name  = module.cluster2.log_group.name
  port            = "9090"

  vpc_id                        = module.dc1_vpc.vpc_id
  vpc_default_security_group_id = module.dc1_vpc.default_security_group_id
  private_subnets               = module.dc1.private_subnets
  public_subnets                = module.dc1.public_subnets

  consul_server_address              = module.dc1.dev_consul_server.server_dns
  consul_server_ca_cert_arn          = module.dc1.dev_consul_server.ca_cert_arn
  consul_ecs_image                   = var.consul_ecs_image
  consul_partition                   = var.dc1_consul_admin_partition
  consul_server_lb_security_group_id = module.dc1.dev_consul_server.lb_security_group_id

  lb_ingress_ip                 = var.lb_ingress_ip
  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
}

module "client_app_dc2" {
  source          = "./client-app"
  datacenter      = local.datacenter_2
  name            = var.name
  region          = var.region
  ecs_cluster_arn = module.cluster3.ecs_cluster.arn
  log_group_name  = module.cluster3.log_group.name
  port            = "9090"

  vpc_id                        = module.dc2_vpc.vpc_id
  vpc_default_security_group_id = module.dc2_vpc.default_security_group_id
  private_subnets               = module.dc2.private_subnets
  public_subnets                = module.dc2.public_subnets

  consul_server_address              = module.dc2.dev_consul_server.server_dns
  consul_server_ca_cert_arn          = module.dc2.dev_consul_server.ca_cert_arn
  consul_ecs_image                   = var.consul_ecs_image
  consul_server_lb_security_group_id = module.dc2.dev_consul_server.lb_security_group_id

  lb_ingress_ip                 = var.lb_ingress_ip
  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
}