# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "terminating-gateway"
    }
  }
}

module "terminating_gateway" {
  source                        = "../../modules/gateway-task"
  family                        = "${var.name}-terminating-gateway"
  ecs_cluster_arn               = aws_ecs_cluster.cluster_one.arn
  subnets                       = module.vpc.private_subnets
  security_groups               = [module.vpc.default_security_group_id]
  log_configuration             = local.log_config
  consul_server_hosts           = module.dc1.dev_consul_server.server_dns
  kind                          = "terminating-gateway"
  tls                           = true
  consul_ca_cert_arn            = module.dc1.dev_consul_server.ca_cert_arn
  additional_task_role_policies = [aws_iam_policy.execute_command.arn]

  acls                     = true
  lb_create_security_group = false
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
