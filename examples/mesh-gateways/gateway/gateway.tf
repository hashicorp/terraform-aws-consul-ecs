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


# resource "aws_security_group" "mesh_gateway" {
#   name   = "${local.example_client_app_name}-alb"
#   vpc_id = var.vpc.vpc_id

#   ingress {
#     description = "Access to example client application."
#     from_port   = 9090
#     to_port     = 9090
#     protocol    = "tcp"
#     cidr_blocks = ["${var.lb_ingress_ip}/32"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# resource "aws_security_group_rule" "ingress_from_client_alb_to_ecs" {
#   type                     = "ingress"
#   from_port                = 0
#   to_port                  = 65535
#   protocol                 = "tcp"
#   source_security_group_id = aws_security_group.example_client_app_alb.id
#   security_group_id        = var.vpc.default_security_group_id
# }

# resource "aws_security_group_rule" "ingress_from_server_alb_to_ecs" {
#   type                     = "ingress"
#   from_port                = 8500
#   to_port                  = 8500
#   protocol                 = "tcp"
#   source_security_group_id = module.dc1.dev_consul_server.lb_security_group_id
#   security_group_id        = var.vpc.default_security_group_id
# }

# resource "aws_lb_target_group" "example_client_app" {
#   name                 = local.example_client_app_name
#   port                 = 9090
#   protocol             = "HTTP"
#   vpc_id               = var.vpc.vpc_id
#   target_type          = "ip"
#   deregistration_delay = 10
#   health_check {
#     path                = "/health"
#     healthy_threshold   = 2
#     unhealthy_threshold = 10
#     timeout             = 30
#     interval            = 60
#   }
# }

# resource "aws_lb_listener" "example_client_app" {
#   load_balancer_arn = aws_lb.example_client_app.arn
#   port              = "9090"
#   protocol          = "HTTP"
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.example_client_app.arn
#   }
# }
