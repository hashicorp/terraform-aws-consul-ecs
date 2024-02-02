# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  // Determine which secrets are provided and which ones need to be created.
  generate_ca              = var.tls && var.generate_ca
  generate_bootstrap_token = var.acls && var.generate_bootstrap_token

  ca_cert_arn         = local.generate_ca ? aws_secretsmanager_secret.ca_cert[0].arn : var.ca_cert_arn
  ca_key_arn          = local.generate_ca ? aws_secretsmanager_secret.ca_key[0].arn : var.ca_key_arn
  bootstrap_token_arn = local.generate_bootstrap_token ? aws_secretsmanager_secret.bootstrap_token[0].arn : var.bootstrap_token_arn
  bootstrap_token     = var.bootstrap_token != "" ? var.bootstrap_token : random_uuid.bootstrap_token.result

  load_balancer = var.lb_enabled ? [{
    target_group_arn = aws_lb_target_group.this[0].arn
    container_name   = "consul-server"
    container_port   = 8500
  }] : var.custom_load_balancer_config

  // Setup Consul server options
  consul_enterprise_enabled          = var.consul_license != ""
  enable_mesh_gateway_wan_federation = var.enable_mesh_gateway_wan_federation || length(var.primary_gateways) > 0 ? true : false
  node_name                          = var.node_name != "" ? var.node_name : var.name

  // If the user has passed an explicit Cloud Map service discovery namespace then use it.
  // Otherwise set the namespace to match the datacenter for the Consul server.
  service_discovery_namespace = var.service_discovery_namespace != "" ? var.service_discovery_namespace : var.datacenter
}

resource "tls_private_key" "ca" {
  count       = local.generate_ca ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "ca" {
  count           = local.generate_ca ? 1 : 0
  private_key_pem = tls_private_key.ca[count.index].private_key_pem

  subject {
    common_name  = "Consul Agent CA"
    organization = "HashiCorp Inc."
  }

  // 5 years.
  validity_period_hours = 43800

  is_ca_certificate  = true
  set_subject_key_id = true

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "aws_secretsmanager_secret" "ca_key" {
  count                   = local.generate_ca ? 1 : 0
  name                    = "${var.name}-ca-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "ca_key" {
  count         = local.generate_ca ? 1 : 0
  secret_id     = aws_secretsmanager_secret.ca_key[count.index].id
  secret_string = tls_private_key.ca[count.index].private_key_pem
}

resource "aws_secretsmanager_secret" "ca_cert" {
  count                   = local.generate_ca ? 1 : 0
  name                    = "${var.name}-ca-cert"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "ca_cert" {
  count         = local.generate_ca ? 1 : 0
  secret_id     = aws_secretsmanager_secret.ca_cert[count.index].id
  secret_string = tls_self_signed_cert.ca[count.index].cert_pem
}

// Optional Enterprise license.
resource "aws_secretsmanager_secret" "license" {
  count                   = local.consul_enterprise_enabled ? 1 : 0
  name                    = "${var.name}-consul-license"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "license" {
  count         = local.consul_enterprise_enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.license[count.index].id
  secret_string = chomp(var.consul_license) // trim trailing newlines
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  network_configuration {
    subnets          = var.subnet_ids
    assign_public_ip = var.assign_public_ip
    security_groups  = [aws_security_group.ecs_service.id]
  }
  launch_type = var.launch_type
  service_registries {
    registry_arn   = aws_service_discovery_service.server.arn
    container_name = "consul-server"
  }
  dynamic "load_balancer" {
    for_each = local.load_balancer
    content {
      target_group_arn = load_balancer.value["target_group_arn"]
      container_name   = load_balancer.value["container_name"]
      container_port   = load_balancer.value["container_port"]
    }
  }
  enable_execute_command = true
  wait_for_steady_state  = var.wait_for_steady_state

  depends_on = [
    aws_iam_role.this_task
  ]
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = var.requires_compatibilities
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.this_execution.arn
  task_role_arn            = aws_iam_role.this_task.arn
  volume {
    name = "consul-data"
  }
  container_definitions = jsonencode(concat(
    local.tls_init_containers,
    [
      {
        name      = "consul-server"
        image     = var.consul_image
        essential = true
        portMappings = [
          {
            containerPort = 8301
          },
          {
            containerPort = 8300
          },
          {
            containerPort = 8500
          }
        ]
        logConfiguration = var.log_configuration
        entryPoint       = ["/bin/sh", "-ec"]
        command          = [replace(local.consul_server_command, "\r", "")]
        mountPoints = [
          {
            sourceVolume  = "consul-data"
            containerPath = "/consul"
          }
        ]
        linuxParameters = {
          initProcessEnabled = true
        }
        dependsOn = var.tls ? [
          {
            containerName = "tls-init"
            condition     = "SUCCESS"
          },
        ] : []
        secrets = concat(
          var.acls ? [
            {
              name      = "CONSUL_HTTP_TOKEN"
              valueFrom = local.bootstrap_token_arn
            },
          ] : [],
          local.consul_enterprise_enabled ? [
            {
              name      = "CONSUL_LICENSE"
              valueFrom = aws_secretsmanager_secret.license[0].arn
            },
          ] : [],
        )
      }
  ]))
}

resource "aws_iam_policy" "this_execution" {
  name        = "${var.name}_execution"
  path        = "/ecs/"
  description = "Consul server execution"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
%{if var.tls~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${local.ca_cert_arn}",
        "${local.ca_key_arn}"
      ]
    },
%{endif~}
%{if var.acls~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${local.bootstrap_token_arn}"
      ]
    },
%{endif~}
%{if local.consul_enterprise_enabled~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${aws_secretsmanager_secret.license[0].arn}"
      ]
    },
%{endif~}
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "this_execution" {
  name = "${var.name}_execution"
  path = "/ecs/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "this_execution" {
  role       = aws_iam_role.this_execution.id
  policy_arn = aws_iam_policy.this_execution.arn
}

resource "aws_iam_role" "this_task" {
  name = "${var.name}_task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  inline_policy {
    name = "exec"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
          ]
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_service_discovery_private_dns_namespace" "server" {
  name        = local.service_discovery_namespace
  description = "The domain name for the Consul dev server in ${var.datacenter}."
  vpc         = var.vpc_id
}

resource "aws_service_discovery_service" "server" {
  name = var.name

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.server.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "random_uuid" "bootstrap_token" {}

resource "aws_secretsmanager_secret" "bootstrap_token" {
  count = local.generate_bootstrap_token ? 1 : 0
  name  = "${var.name}-bootstrap-token"
}

resource "aws_secretsmanager_secret_version" "bootstrap_token" {
  count         = local.generate_bootstrap_token ? 1 : 0
  secret_id     = aws_secretsmanager_secret.bootstrap_token[count.index].id
  secret_string = local.bootstrap_token
}

locals {
  // TODO: Deprecated fields
  //   The 'ca_file' field is deprecated. Use the 'tls.defaults.ca_file' field instead.
  //   The 'cert_file' field is deprecated. Use the 'tls.defaults.cert_file' field instead.
  //   The 'key_file' field is deprecated. Use the 'tls.defaults.key_file' field instead.
  //   The 'verify_incoming_rpc' field is deprecated. Use the 'tls.internal_rpc.verify_incoming' field instead.
  //   The 'verify_outgoing' field is deprecated. Use the 'tls.defaults.verify_outgoing' field instead.
  //   The 'verify_server_hostname' field is deprecated. Use the 'tls.internal_rpc.verify_server_hostname' field instead.
  //   The 'acl.tokens.master' field is deprecated. Use the 'acl.tokens.initial_management' field instead.
  consul_server_command = <<EOF
ECS_IPV4=$(curl -s $ECS_CONTAINER_METADATA_URI_V4 | jq -r '.Networks[0].IPv4Addresses[0]')

exec consul agent -server \
  -bootstrap \
  -ui \
  -advertise "$ECS_IPV4" \
  -client 0.0.0.0 \
  -data-dir /tmp/consul-data \
  -hcl 'node_name = "${local.node_name}"' \
  -hcl='datacenter = "${var.datacenter}"' \
  -hcl 'connect { enabled = true }' \
  -hcl 'enable_central_service_config = true' \
%{if var.tls~}
  -hcl='ca_file = "/consul/consul-agent-ca.pem"' \
  -hcl='cert_file = "/consul/${var.datacenter}-server-consul-0.pem"' \
  -hcl='key_file = "/consul/${var.datacenter}-server-consul-0-key.pem"' \
  -hcl='auto_encrypt = {allow_tls = true}' \
%{if local.is_consul_1_14_plus~}
  -hcl='ports { https = 8501, grpc_tls = 8503 }' \
%{else~}
  -hcl='ports { https = 8501, grpc = 8502 }' \
%{endif~}
  -hcl='verify_incoming_rpc = true' \
  -hcl='verify_outgoing = true' \
  -hcl='verify_server_hostname = true' \
%{else~}
  -hcl='ports { grpc = 8502 }' \
%{endif~}
%{if var.acls~}
  -hcl='acl {enabled = true, default_policy = "deny", down_policy = "extend-cache", enable_token_persistence = true}' \
  -hcl='acl = { tokens = { master = "${local.bootstrap_token}", agent = "${local.bootstrap_token}" }}' \
%{endif~}
%{if var.acls && local.enable_mesh_gateway_wan_federation~}
  -hcl='acl = { enable_token_replication = true }' \
%{endif~}
%{if var.acls && var.replication_token != ""~}
  -hcl='acl = { tokens = { replication = "${var.replication_token}"}}' \
%{endif~}
%{if var.primary_datacenter != ""~}
  -hcl='primary_datacenter = "${var.primary_datacenter}"' \
%{endif~}
%{if length(var.retry_join_wan) > 0~}
  -hcl='retry_join_wan = [
  %{for addr in var.retry_join_wan~}
    "${addr}",
  %{endfor~}
  ]' \
%{endif~}
%{if local.enable_mesh_gateway_wan_federation~}
  -hcl='connect { enable_mesh_gateway_wan_federation = true }' \
%{endif~}
%{if var.enable_cluster_peering~}
  -hcl='peering { enabled = true }' \
%{endif~}
%{if length(var.primary_gateways) > 0~}
  -hcl='primary_gateways = [
  %{for addr in var.primary_gateways~}
    "${addr}",
  %{endfor~}
  ]' \
%{endif~}
%{if var.primary_datacenter != ""~}
  -hcl='primary_datacenter = "${var.primary_datacenter}"' \
%{endif~}
%{if length(var.retry_join_wan) > 0~}
  -hcl='retry_join_wan = [
  %{for addr in var.retry_join_wan~}
    "${addr}",
  %{endfor~}
  ]' \
%{endif~}
%{if local.enable_mesh_gateway_wan_federation~}
  -hcl='connect { enable_mesh_gateway_wan_federation = true }' \
%{endif~}
%{if length(var.primary_gateways) > 0~}
  -hcl='primary_gateways = [
  %{for addr in var.primary_gateways~}
    "${addr}",
  %{endfor~}
  ]' \
%{endif~}
EOF

  // We use this command to generate the server certs dynamically before the servers start
  // because we need to add the IP of the task as a SAN to the certificate, and we don't know that
  // IP ahead of time.
  consul_server_tls_init_command = <<EOF
ECS_IPV4=$(curl -s $ECS_CONTAINER_METADATA_URI_V4 | jq -r '.Networks[0].IPv4Addresses[0]')
cd /consul
echo "$CONSUL_CACERT_PEM" > ./consul-agent-ca.pem
echo "$CONSUL_CAKEY" > ./consul-agent-ca-key.pem
consul tls cert create -server \
  -node="${local.node_name}" \
  -dc="${var.datacenter}" \
  -additional-ipaddress=$ECS_IPV4 \
  -additional-dnsname="${var.name}.${local.service_discovery_namespace}" \
%{if length(var.additional_dns_names) > 0~}
  %{for dnsname in var.additional_dns_names~}
    -additional-dnsname="${dnsname}" \
  %{endfor~}
%{endif~}
EOF

  tls_init_container = {
    name             = "tls-init"
    image            = var.consul_image
    essential        = false
    logConfiguration = var.log_configuration
    mountPoints = [
      {
        sourceVolume  = "consul-data"
        containerPath = "/consul"
      }
    ]
    entryPoint = ["/bin/sh", "-ec"]
    command    = [local.consul_server_tls_init_command]
    secrets = var.tls ? [
      {
        name      = "CONSUL_CACERT_PEM",
        valueFrom = local.ca_cert_arn
      },
      {
        name      = "CONSUL_CAKEY",
        valueFrom = local.ca_key_arn
      }
    ] : []
  }
  tls_init_containers = var.tls ? [local.tls_init_container] : []
}

resource "aws_lb_target_group" "this" {
  count                = var.lb_enabled ? 1 : 0
  name                 = var.name
  port                 = 8500
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 10
  health_check {
    path                = "/v1/status/leader"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    interval            = 60
  }
}

resource "aws_lb" "this" {
  count              = var.lb_enabled ? 1 : 0
  name               = var.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load_balancer[count.index].id]
  subnets            = var.lb_subnets
}

resource "aws_lb_listener" "this" {
  count             = var.lb_enabled ? 1 : 0
  load_balancer_arn = aws_lb.this[count.index].arn
  port              = "8500"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[count.index].arn
  }
}

resource "aws_security_group" "load_balancer" {
  count  = var.lb_enabled ? 1 : 0
  name   = "${var.name}-lb-sg"
  vpc_id = var.vpc_id

  ingress {
    description     = "Access to Consul dev server HTTP API and UI."
    from_port       = 8500
    to_port         = 8500
    protocol        = "tcp"
    cidr_blocks     = var.lb_ingress_rule_cidr_blocks
    security_groups = var.lb_ingress_rule_security_groups
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_service" {
  name   = "${var.name}-ecs-sg"
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "lb_ingress_to_service" {
  count = var.lb_enabled ? 1 : 0

  description              = "Access to Consul dev server from security group attached to load balancer"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.load_balancer[0].id
  security_group_id        = aws_security_group.ecs_service.id
}


resource "aws_security_group_rule" "egress_from_service" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_service.id
}

// Create a null_resource that will wait for the Consul server to be available via its ALB.
// This allows us to wait until the Consul server is reachable so that callers can always
// create Consul resources like config entries via Terraform without failures. 
resource "null_resource" "wait_for_consul_server" {
  count = var.lb_enabled ? 1 : 0
  triggers = {
    // Trigger update when Consul server ALB DNS name changes.
    consul_server_lb_dns_name = "${aws_lb.this[0].dns_name}"
  }
  provisioner "local-exec" {
    command = <<EOT
stopTime=$(($(date +%s) + ${var.consul_server_startup_timeout})) ; \
while [ $(date +%s) -lt $stopTime ] ; do \
  sleep 10 ; \
  statusCode=$(curl -s -o /dev/null -w '%%{http_code}' http://${aws_lb.this[0].dns_name}:8500/v1/catalog/services)
  [ $statusCode -eq 200 ] && break; \
done
EOT
  }
}
