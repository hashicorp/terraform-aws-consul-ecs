# Copyright IBM Corp. 2021, 2025
# SPDX-License-Identifier: MPL-2.0

locals {
  log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "api-gateway"
    }
  }
}

module "api_gateway" {
  source                        = "../../modules/gateway-task"
  family                        = "${var.name}-api-gateway"
  ecs_cluster_arn               = aws_ecs_cluster.this.arn
  subnets                       = module.vpc.private_subnets
  security_groups               = [module.vpc.default_security_group_id]
  log_configuration             = local.log_config
  consul_server_hosts           = module.dc1.dev_consul_server.server_dns
  kind                          = "api-gateway"
  tls                           = true
  consul_ca_cert_arn            = module.dc1.dev_consul_server.ca_cert_arn
  additional_task_role_policies = [aws_iam_policy.execute_command.arn]

  acls = true

  lb_create_security_group = false
  enable_transparent_proxy = false

  custom_load_balancer_config = [{
    container_name   = "consul-dataplane"
    container_port   = 8443
    target_group_arn = aws_lb_target_group.this.arn
  }]
}

# Ingress rule for the API Gateway task that accepts traffic from the API gateway's LB
resource "aws_security_group_rule" "gateway_task_ingress_rule" {
  type                     = "ingress"
  description              = "Ingress rule for ${var.name}-api-gateway task"
  from_port                = 8443
  to_port                  = 8443
  protocol                 = "-1"
  source_security_group_id = aws_security_group.load_balancer.id
  security_group_id        = module.vpc.default_security_group_id
}

# API gateway's config entry
resource "consul_config_entry" "api_gateway_entry" {
  depends_on = [module.dc1]
  name       = "${var.name}-api-gateway"
  kind       = "api-gateway"

  config_json = jsonencode({
    Listeners = [
      {
        Name     = "api-gw-http-listener"
        Port     = 8443
        Protocol = "http"
      }
    ]
  })

  provider = consul.dc1-cluster
}

// Intention to allow traffic from the client app to the server app
resource "consul_config_entry" "client_server_intention" {
  depends_on = [module.dc1]

  kind     = "service-intentions"
  name     = "${var.name}-example-server-app"
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Sources = [
      {
        Name       = "${var.name}-example-client-app"
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      }
    ]
  })
}

// Intention to allow traffic from the API gateway to the client app
resource "consul_config_entry" "gateway_client_intention" {
  depends_on = [module.dc1]

  kind     = "service-intentions"
  name     = "${var.name}-example-client-app"
  provider = consul.dc1-cluster

  config_json = jsonencode({
    Sources = [
      {
        Name       = "${var.name}-api-gateway"
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      }
    ]
  })
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