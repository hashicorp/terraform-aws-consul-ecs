locals {
  clients = tomap({ for c in range(3) : "agent${c}" => {
    index : c,
    subnet_id : module.vpc.private_subnets[c],
    command : format(local.consul_client_command_template, c)
  } })

  consul_client_command_template = <<EOF
set +ex
ECS_IPV4=$(curl -s $ECS_CONTAINER_METADATA_URI_V4 | jq -r '.Networks[0].IPv4Addresses[0]')
mkdir -p /tmp/consul-data
echo "$CONSUL_CACERT_PEM" > /tmp/consul-data/consul-agent-ca.pem

exec consul agent \
  -advertise "$ECS_IPV4" \
  -client 0.0.0.0 \
  -data-dir "/tmp/consul-data" \
  -encrypt "$CONSUL_GOSSIP_ENCRYPTION_KEY" \
  -hcl='node_name = "consul-agent%s"' \
  -hcl='datacenter = "${local.datacenter}"' \
  -hcl='connect { enabled = true }' \
  -hcl='leave_on_terminate = true' \
  -hcl='auto_encrypt { tls = true }' \
  -hcl='tls { defaults { ca_file = "/tmp/consul-data/consul-agent-ca.pem" }}' \
  -hcl='tls { defaults { verify_incoming = true, verify_outgoing = true }}' \
  -hcl='tls { internal_rpc { verify_server_hostname = true }}' \
  -hcl='ports { server = 8300, serf_lan = 8301, serf_wan = 8302, https = 8501, grpc = 8502, grpc_tls = 8503 }' \
  -retry-join "provider=aws tag_key=Consul-Auto-Join tag_value=consul service=ecs"
EOF

  client_portmap = [{
    containerPort : 8300,
    hostPort : 8300,
    protocol : "tcp"
    }, {
    containerPort : 8301,
    hostPort : 8301,
    protocol : "tcp"
    }, {
    containerPort : 8302,
    hostPort : 8302,
    protocol : "tcp"
    }, {
    containerPort : 8500,
    hostPort : 8500,
    protocol : "tcp"
    }, {
    containerPort : 8501,
    hostPort : 8501,
    protocol : "tcp"
    }, {
    containerPort : 8502,
    hostPort : 8502,
    protocol : "tcp"
    }, {
    containerPort : 8600,
    hostPort : 8600,
    protocol : "udp"
  }]
}

resource "aws_lb_target_group" "agent" {
  for_each    = local.clients
  name        = title(each.key)
  port        = 8500
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  slow_start  = 30

  health_check {
    enabled             = true
    path                = "/v1/status/leader"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 2
    interval            = 5
  }
}

resource "aws_lb_listener" "agent" {
  load_balancer_arn = module.consul-cluster.mgmt_alb_arn
  port              = "8500"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-2019-08"
  certificate_arn   = module.consul-cluster.alb_iam_cert_arn

  default_action {
    type = "forward"
    forward {
      dynamic "target_group" {
        for_each = aws_lb_target_group.agent
        content {
          arn = aws_lb_target_group.agent[target_group.key].arn
        }
      }
    }
  }
}

module "consul-clients" {
  source   = "../../modules/ecs-service"
  for_each = local.clients

  name       = title(each.key)
  vpc_id     = module.vpc.vpc_id
  subnet_ids = [each.value["subnet_id"]]

  ecs_cluster_name = aws_ecs_cluster.ecs.name

  target_groups = {
    consul8500 : {
      protocol : "TCP"
      port : 8500
      arn : aws_lb_target_group.agent[each.key].arn
    }
  }

  container_name   = "consul-agent"
  cpu              = 2048
  memory           = 4096
  cpu_architecture = "ARM64"

  task_definition = [
    {
      name : "consul-agent"
      image : var.consul_image
      cpu : 2048
      memory : 4096
      essential : true
      entryPoint : ["/bin/sh", "-ec"]
      command : [replace(each.value["command"], "\r", "")]
      linuxParameters : {
        initProcessEnabled : true
      }
      portMappings : local.client_portmap
      secrets : [
        {
          name      = "CONSUL_GOSSIP_ENCRYPTION_KEY"
          valueFrom = module.consul-cluster.gossip_key_arn
        },
        {
          name      = "CONSUL_CACERT_PEM",
          valueFrom = module.consul-cluster.ca_cert_arn
        },
      ]
      healthCheck : {
        retries : 3,
        command : ["CMD-SHELL", "curl http://127.0.0.1:8500/v1/status/leader"],
        timeout : 5,
        interval : 30,
        startPeriod : 15,
      }
      logConfiguration : {
        logDriver : "awslogs",
        options : {
          awslogs-group : module.consul-cluster.cloudwatch_log_group_name,
          awslogs-region : data.aws_region.current.name,
          awslogs-stream-prefix : "consul-agent"
        }
      }
    }
  ]

  security_group_ids = [
    module.consul-cluster.consul_server_security_group_id,
  ]
  ecs_execution_role_arn = aws_iam_role.client_execution_role.arn
  ecs_task_role_arn      = aws_iam_role.client_task_role.arn
  ecs_task_role_id       = aws_iam_role.client_task_role.id

  depends_on = [
    aws_lb_target_group.agent,
    module.consul-cluster,
  ]
}

data "aws_iam_policy_document" "client_execution" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [
      data.aws_kms_alias.secretsmanager.arn,
      data.aws_kms_alias.secretsmanager.target_key_arn,
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      module.consul-cluster.gossip_key_arn,
      module.consul-cluster.ca_key_arn,
      module.consul-cluster.ca_cert_arn,
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:consul/${local.datacenter}/tls/CONSUL_CLIENT_*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "client_execution" {
  name   = "${title(var.name)}Execution"
  role   = aws_iam_role.client_execution_role.id
  policy = data.aws_iam_policy_document.client_execution.json
}

data "aws_iam_policy_document" "client_execution_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ecs-tasks.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "client_execution_role" {
  name        = "${title(var.name)}Execution"
  path        = "/ecs/"
  description = "Consul client execution role"

  assume_role_policy = data.aws_iam_policy_document.client_execution_assume.json

}

data "aws_iam_policy_document" "client_task_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ecs-tasks.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "client_task" {
  statement {
    sid    = "${title(replace(var.name, "-", ""))}AutoDiscover"
    effect = "Allow"
    actions = [
      "ecs:ListClusters",
      "ecs:ListServices",
      "ecs:DescribeServices",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
      "ecs:DescribeContainerInstances",
      "ec2:DescribeNetworkInterfaces",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "client_task" {
  name   = "${title(var.name)}Task"
  policy = data.aws_iam_policy_document.client_task.json
  role   = aws_iam_role.client_task_role.id
}

#data "aws_iam_policy_document" "ecs_datadog" {
#  statement {
#    sid    = "${title(replace(var.name, "-", ""))}Datadog"
#    effect = "Allow"
#    actions = [
#      "ecs:ListClusters",
#      "ecs:ListContainerInstances",
#      "ecs:DescribeContainerInstances",
#    ]
#    resources = ["*"]
#  }
#}
#
#resource "aws_iam_role_policy" "ecs_datadog" {
#  name   = "${title(replace(var.name, "-", ""))}Datadog"
#  policy = data.aws_iam_policy_document.ecs_datadog.json
#  role   = aws_iam_role.client_task_role.id
#}

resource "aws_iam_role" "client_task_role" {
  name               = "${title(var.name)}Task"
  assume_role_policy = data.aws_iam_policy_document.client_task_assume.json
}
