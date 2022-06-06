locals {
  mgw_name_1 = "${var.name}-${local.primary_datacenter}-mesh-gateway"
  mgw_name_2 = "${var.name}-${local.secondary_datacenter}-mesh-gateway"
}

module "dc1_gateway" {
  source          = "./gateway"
  name            = local.mgw_name_1
  region          = var.region
  vpc             = module.dc1_vpc
  private_subnets = module.dc1_vpc.private_subnets
  public_subnets  = module.dc1_vpc.public_subnets
  cluster         = module.dc1.ecs_cluster.arn
  log_group_name  = module.dc1.log_group.name
  datacenter      = local.primary_datacenter
  retry_join      = module.dc1.retry_join
  ca_cert_arn     = module.dc1.ca_cert_secret_arn
  gossip_key_arn  = module.dc1.gossip_key_secret_arn
  consul_image    = var.consul_image

  consul_http_addr                   = module.dc1.consul_private_endpoint_url
  enable_mesh_gateway_wan_federation = true

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]

  primary_datacenter = local.primary_datacenter
}

// DC2 gateway
module "dc2_gateway" {
  source          = "./gateway"
  name            = local.mgw_name_2
  region          = var.region
  vpc             = module.dc2_vpc
  private_subnets = module.dc2_vpc.private_subnets
  public_subnets  = module.dc2_vpc.public_subnets
  cluster         = module.dc2.ecs_cluster.arn
  log_group_name  = module.dc2.log_group.name
  datacenter      = local.secondary_datacenter
  retry_join      = module.dc2.retry_join
  ca_cert_arn     = module.dc2.ca_cert_secret_arn
  gossip_key_arn  = module.dc2.gossip_key_secret_arn
  consul_image    = var.consul_image

  consul_http_addr                   = module.dc2.consul_private_endpoint_url
  enable_mesh_gateway_wan_federation = true

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]

  primary_datacenter = local.primary_datacenter
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
