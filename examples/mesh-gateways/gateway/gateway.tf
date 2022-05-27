locals {
  log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = var.log_group_name
      awslogs-region        = var.region
      awslogs-stream-prefix = "mesh-gateway"
    }
  }
}

module "mesh_gateway" {
  source                             = "../../../modules/gateway-task"
  family                             = var.name
  log_configuration                  = local.log_config
  retry_join                         = var.retry_join
  kind                               = "mesh-gateway"
  consul_datacenter                  = var.datacenter
  enable_mesh_gateway_wan_federation = var.enable_mesh_gateway_wan_federation
  tls                                = true
  consul_server_ca_cert_arn          = var.ca_cert_arn
  gossip_key_secret_arn              = var.gossip_key_arn
  wan_address                        = aws_lb.mesh_gateway.dns_name
  wan_port                           = 8443
  additional_task_role_policies      = var.additional_task_role_policies

  consul_ecs_image = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:0d327c1"
}

resource "aws_ecs_service" "mesh_gateway" {
  // Mesh-init '-mesh-gateway' but we need it here to distinguish the service.
  name            = var.name
  cluster         = var.cluster
  task_definition = module.mesh_gateway.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets = var.private_subnets
  }
  launch_type    = "FARGATE"
  propagate_tags = "TASK_DEFINITION"
  load_balancer {
    target_group_arn = aws_lb_target_group.mesh_gateway.arn
    container_name   = "sidecar-proxy"
    container_port   = 8443
  }
  enable_execute_command = true
}

resource "aws_lb" "mesh_gateway" {
  name               = var.name
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnets
}

resource "aws_lb_target_group" "mesh_gateway" {
  name                 = var.name
  port                 = "8443"
  protocol             = "TCP"
  target_type          = "ip"
  vpc_id               = var.vpc.vpc_id
  deregistration_delay = 120
  health_check {
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "mesh_gateway" {
  load_balancer_arn = aws_lb.mesh_gateway.arn
  port              = "8443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mesh_gateway.arn
  }
}

// TODO: Ingress to each mesh gateway should only be allowed from the other
// mesh gateway. This rule allows ALL public internet traffic to reach the
// mesh gateway through the NLB. This is for testing only and is not secure.
// Not sure how to do this in terraform without creating a cyclic dependency:
// - MGW's require a Public IP or an NLB because they use TCP (layer 4)
// - NLBs don't support security groups
// - Don't know the Public IPs of the task (or NLB) until after apply.
resource "aws_security_group_rule" "ingress_from_internet" {
  type              = "ingress"
  description       = "TEST ONLY - public internet to NLB"
  from_port         = 8443
  to_port           = 8443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"] // TODO: limit this to the other mesh gateway.
  security_group_id = var.vpc.default_security_group_id
}
