locals {
  client_suffix = random_string.client_suffix.result
}

resource "random_string" "client_suffix" {
  length  = 6
  special = false
}

// Create ACL controller
module "acl_controller_client" {
  source = "../../../modules/acl-controller"
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "consul-acl-controller-${local.client_suffix}"
    }
  }
  launch_type                       = local.launch_type
  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn
  consul_server_http_addr           = hcp_consul_cluster.this.consul_private_endpoint_url
  ecs_cluster_arn                   = aws_ecs_cluster.cluster_1.arn
  region                            = var.region
  subnets                           = module.vpc.private_subnets
  name_prefix                       = local.client_suffix
  consul_ecs_image                  = var.consul_ecs_image
  consul_partitions_enabled         = true
  consul_partition                  = consul_admin_partition.part1.name
}

// Create services.
resource "aws_ecs_service" "example_client" {
  name            = "example_client_${local.client_suffix}"
  cluster         = aws_ecs_cluster.cluster_1.arn
  task_definition = module.example_client.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = module.vpc.private_subnets
  }
  launch_type            = local.launch_type
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true

  tags = var.tags
}

module "example_client" {
  source = "../../../modules/mesh-task"
  family = "example_client_${local.client_suffix}"
  container_definitions = [{
    name      = "basic"
    image     = "docker.mirror.hashicorp.services/nicholasjackson/fake-service:v0.21.0"
    essential = true
    environment = [
      {
        name  = "UPSTREAM_URIS"
        value = "http://localhost:1234"
      }
    ]
    linuxParameters = {
      initProcessEnabled = true
    }
  }]
  retry_join = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["retry_join"]
  upstreams = [
    {
      destinationName      = "example_server_${local.server_suffix}"
      destinationPartition = consul_admin_partition.part2.name
      destinationNamespace = consul_namespace.ns2.name
      localBindPort        = 1234
    }
  ]
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "example_client_${local.client_suffix}"
    }
  }
  outbound_only = true

  tls                       = true
  acls                      = true
  gossip_key_secret_arn     = aws_secretsmanager_secret.gossip_key.arn
  consul_server_ca_cert_arn = aws_secretsmanager_secret.consul_ca_cert.arn
  consul_ecs_image          = var.consul_ecs_image
  consul_partition          = consul_admin_partition.part1.name
  consul_namespace          = consul_namespace.ns1.name
  consul_image              = var.consul_image

  additional_task_role_policies = [aws_iam_policy.execute_command.arn]
}
