resource "aws_ecs_cluster" "this" {
  name               = local.name
  capacity_providers = ["FARGATE"]
  tags               = var.tags
}

module "acl_controller" {
  source = "../../../../modules/acl-controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "${local.name}-acl-controller"
    }
  }
  launch_type                       = var.launch_type
  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn
  consul_server_http_addr           = "${module.consul-server.consul_server_address}:8500"
  datadog_api_key                   = var.datadog_api_key
  ecs_cluster_arn                   = aws_ecs_cluster.this.arn
  region                            = var.region
  subnets                           = module.vpc.private_subnets
  name_prefix                       = random_string.secret_suffix.result
  consul_ecs_image                  = var.consul_ecs_image
}


module "service_group" {
  count                              = var.service_groups
  client_instances_per_service_group = var.client_instances_per_service_group
  server_instances_per_service_group = var.server_instances_per_service_group
  source                             = "./service-group"
  name                               = "${local.name}-${count.index}"
  gossip_key_secret_arn              = aws_secretsmanager_secret.gossip_key.arn
  datadog_api_key                    = var.datadog_api_key
  consul_ecs_image                   = var.consul_ecs_image
  region                             = var.region
  additional_task_role_policies      = [aws_iam_policy.consul_retry_join.arn]
  suffix                             = random_string.secret_suffix.result
  log_group_name                     = aws_cloudwatch_log_group.log_group.name
  ca_cert_arn                        = aws_secretsmanager_secret.ca_cert.arn
  tags                               = var.tags
  launch_type                        = var.launch_type
  private_subnets                    = module.vpc.private_subnets
  cluster_arn                        = aws_ecs_cluster.this.arn
  consul_client_token_secret_arn     = module.acl_controller.client_token_secret_arn
}


resource "consul_config_entry" "proxy-defaults" {
  kind = "proxy-defaults"
  name = "global"

  config_json = jsonencode({
    Config = {
      protocol            = "http"
      envoy_dogstatsd_url = "udp://127.0.0.1:8125"
    }
  })

  depends_on = [module.consul-server]
}

resource "consul_config_entry" "service_intentions" {
  kind = "service-intentions"
  name = "*"

  config_json = jsonencode({
    Sources = [
      {
        Action = "allow"
        Name   = "*"
      }
    ]
  })

  depends_on = [module.consul-server]
}
