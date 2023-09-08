# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  example_client_app_name = "${var.name}-example-client-app"
  example_client_app_log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "${var.name}-load-client"
    }
  }
}

module "load_client" {
  source              = "../../../../../modules/mesh-task"
  family              = local.example_client_app_name
  port                = 9090
  acls                = true
  consul_server_hosts = var.consul_server_hosts
  tls                 = true
  consul_ca_cert_arn  = var.consul_ca_cert_arn
  log_configuration   = local.example_client_app_log_config
  container_definitions = [{
    name             = "load-client"
    image            = "ghcr.io/erichaberkorn/slow_cooker:latest" // Using a clone to avoid rate limits
    essential        = true
    logConfiguration = local.example_client_app_log_config
    command = [
      "-qps", "1",
      "-concurrency", "3",
      "-metric-addr", "0.0.0.0:9102",
      "http://127.0.0.1:1235",
    ]
    linuxParameters = {
      initProcessEnabled = true
    }
    },
    {
      name             = "datadog-agent"
      image            = "ghcr.io/erichaberkorn/datadog_agent:latest"
      essential        = true
      logConfiguration = local.example_client_app_log_config
      environment = [
        {
          name  = "DD_API_KEY"
          value = var.datadog_api_key
        },
        {
          name  = "ECS_FARGATE"
          value = "true"
        },
        {
          name  = "DD_APM_ENABLED",
          value = "true"
        },
        {
          name  = "DD_SITE",
          value = "us5.datadoghq.com"
        }
      ]
      dockerLabels = {
        "com.datadoghq.ad.check_names"  = "[\"openmetrics\"]"
        "com.datadoghq.ad.init_configs" = "[{}]"
        "com.datadoghq.ad.instances" = jsonencode([
          {
            prometheus_url            = "http://%%host%%:9102/metrics"
            namespace                 = "slow_cooker"
            metrics                   = ["go_*", "latency*", "requests", "successes", "process*"]
            send_distribution_buckets = true
          }
        ])
      }
  }]

  upstreams = [
    {
      destinationName = local.example_server_app_name
      localBindPort   = 1235
    }
  ]

  additional_task_role_policies = var.additional_task_role_policies
  consul_ecs_image              = var.consul_ecs_image
  consul_partition              = "default"
  consul_namespace              = "default"
}

resource "aws_ecs_service" "load_client_app" {
  name            = local.example_client_app_name
  cluster         = var.ecs_cluster_arn
  task_definition = module.load_client.task_definition_arn
  desired_count   = var.client_instances_per_group
  network_configuration {
    subnets = var.private_subnets
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}