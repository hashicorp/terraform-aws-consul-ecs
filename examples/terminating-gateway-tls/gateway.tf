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

data "aws_efs_file_system" "efs_id" {
  file_system_id = aws_efs_file_system.certs_efs.id
}

module "terminating_gateway" {
  source                        = "../../modules/gateway-task"
  family                        = "${var.name}-terminating-gateway"
  enable_transparent_proxy      = false
  ecs_cluster_arn               = aws_ecs_cluster.cluster_one.arn
  subnets                       = module.vpc.private_subnets
  security_groups               = [module.vpc.default_security_group_id]
  log_configuration             = local.log_config
  consul_server_hosts           = module.dc1.dev_consul_server.server_dns
  kind                          = "terminating-gateway"
  tls                           = true
  consul_ca_cert_arn            = module.dc1.dev_consul_server.ca_cert_arn
  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
  volumes = [
    {
      name      = "certs-efs"
      host_path = "/efs"
      efs_volume_configuration = {
        file_system_id = data.aws_efs_file_system.efs_id.id
        root_directory = "/"
      }
    }
  ]

  acls                     = true
  lb_create_security_group = false
}

resource "consul_config_entry" "terminating_gateway" {
  name       = "${var.name}-terminating-gateway"
  kind       = "terminating-gateway"
  depends_on = [module.terminating_gateway]
  config_json = jsonencode({
    Services = [{
      Name     = "${var.name}-external-server-app"
      CAFile   = "${var.certs_mount_path}/ca.cert"
      KeyFile  = "${var.certs_mount_path}/gateway.key"
      CertFile = "${var.certs_mount_path}/gateway.cert"
      SNI      = "*"
    }]
  })
  provider = consul.dc1-cluster
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