# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# Run the Consul dev server as an ECS task.
module "dc1" {
  name            = var.name
  region          = var.region
  source          = "./datacenter"
  ecs_cluster_arn = aws_ecs_cluster.this.arn
  private_subnets = module.vpc.private_subnets
  public_subnets  = module.vpc.public_subnets
  vpc             = module.vpc
  lb_ingress_ip   = var.lb_ingress_ip
  log_group_name  = aws_cloudwatch_log_group.log_group.name
}
