# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module "service_group" {
  count  = var.desired_service_groups
  source = "./service_group"

  name            = "${var.name}-${count.index}"
  region          = var.region
  ecs_cluster_arn = aws_ecs_cluster.this.arn
  log_group_name  = aws_cloudwatch_log_group.log_group.name
  private_subnets = module.vpc.private_subnets

  consul_server_hosts = module.dev_consul_server.server_dns
  consul_ca_cert_arn  = aws_secretsmanager_secret.ca_cert.arn
  consul_ecs_image    = var.consul_ecs_image

  datadog_api_key               = var.datadog_api_key
  server_instances_per_group    = var.server_instances_per_group
  client_instances_per_group    = var.client_instances_per_group
  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
}

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