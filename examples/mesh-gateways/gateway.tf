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
  retry_join      = [module.dc1.dev_consul_server.server_dns]
  ca_cert_arn     = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_arn  = aws_secretsmanager_secret.gossip_key.arn

  enable_mesh_gateway_wan_federation = true

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
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
  retry_join      = [module.dc2.dev_consul_server.server_dns]
  ca_cert_arn     = aws_secretsmanager_secret.ca_cert.arn
  gossip_key_arn  = aws_secretsmanager_secret.gossip_key.arn

  enable_mesh_gateway_wan_federation = true

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
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
