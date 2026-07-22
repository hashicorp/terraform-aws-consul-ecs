terraform {
  required_version = ">= 0.13"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_kms_alias" "secretsmanager" {
  name = "alias/aws/secretsmanager"
}

# ---------------------------------------------------------------------------------------------------------------------
# Create variables and ssh keys
# ---------------------------------------------------------------------------------------------------------------------

locals {
  // Determine which secrets are provided and which ones need to be created.
  generate_gossip_key      = var.gossip_encryption_enabled && var.generate_gossip_encryption_key
  generate_ca              = var.tls ? var.generate_ca : false
  generate_bootstrap_token = var.acls ? var.generate_bootstrap_token : false

  gossip_key_arn      = local.generate_gossip_key ? aws_secretsmanager_secret.gossip_key[0].arn : var.gossip_key_secret_arn
  ca_cert_arn         = local.generate_ca ? aws_secretsmanager_secret.certs["CONSUL_CA"].arn : var.ca_cert_arn
  ca_key_arn          = local.generate_ca ? aws_secretsmanager_secret.certs["CONSUL_CA_KEY"].arn : var.ca_key_arn
  bootstrap_token_arn = local.generate_bootstrap_token ? aws_secretsmanager_secret.bootstrap_token[0].arn : var.bootstrap_token_arn
  bootstrap_token     = var.acls ? var.generate_bootstrap_token ? random_uuid.bootstrap_token[0].result : var.bootstrap_token : null

  // Setup Consul server options
  consul_enterprise_enabled          = var.consul_license != ""
  enable_mesh_gateway_wan_federation = var.enable_mesh_gateway_wan_federation || length(var.primary_gateways) > 0 ? true : false
  node_name                          = var.node_name != "" ? var.node_name : var.name

  // If the user has passed an explicit Cloud Map service discovery namespace then use it.
  // Otherwise set the namespace to match the datacenter for the Consul server.
  service_discovery_namespace = var.service_discovery_namespace != "" ? var.service_discovery_namespace : var.datacenter

  certs = {
    CONSUL_CA : "consul-agent-ca.pem"
    CONSUL_CA_KEY : "consul-agent-ca-key.pem"
    CONSUL_ALB_KEY : "${var.datacenter}-server-consul-0-key.pem"
    CONSUL_ALB_CERT : "${var.datacenter}-server-consul-0.pem"
    CONSUL_CLIENT_KEY : "${var.datacenter}-client-consul-0-key.pem"
    CONSUL_CLIENT_CERT : "${var.datacenter}-client-consul-0.pem"
  }
  cert_arns = [for cert in aws_secretsmanager_secret.certs : cert.arn]

  server_map = tomap({ for c in range(var.consul_count) : "consul${c}" => {
    index : c
    subnet_id : var.private_subnet_ids[c]
    owner_gid : 1000
    owner_uid : 100
    permissions : "0700"
    command : format(local.consul_server_command_template, c)
    init : var.tls ? [{
      name      = "tls-init"
      image     = var.consul_image
      essential = false
      logConfiguration = {
        logDriver : "awslogs",
        options : {
          awslogs-group : aws_cloudwatch_log_group.container-logs.name,
          awslogs-region : data.aws_region.current.name,
          awslogs-stream-prefix : "tls-init"
        }
      }
      mountPoints = var.deploy_efs_cluster ? [
        {
          containerPath : "/consul"
          sourceVolume : "consul${c}"
          readOnly : false
        }
      ] : []
      entryPoint = ["/bin/sh", "-ec"]
      command    = [format(local.consul_server_tls_init_command_template, c, c)]
      secrets = [
        {
          name      = "CONSUL_CACERT_PEM",
          valueFrom = local.ca_cert_arn
        },
        {
          name      = "CONSUL_CAKEY",
          valueFrom = local.ca_key_arn
        }
      ]
    }] : []
  } })

  consul_server_command_template = <<EOF
ECS_IPV4=$(curl -s $ECS_CONTAINER_METADATA_URI_V4 | jq -r '.Networks[0].IPv4Addresses[0]')

exec consul agent -server \
  -bootstrap-expect ${var.consul_count} \
  -ui \
  -advertise "$ECS_IPV4" \
  -client 0.0.0.0 \
  -data-dir ${var.deploy_efs_cluster ? "/consul/data" : "/tmp/consul-data"} \
%{if var.gossip_encryption_enabled~}
  -encrypt "$CONSUL_GOSSIP_ENCRYPTION_KEY" \
%{endif~}
  -hcl='node_name = "${local.node_name}%s"' \
  -hcl='datacenter = "${var.datacenter}"' \
  -hcl='connect { enabled = true }' \
  -hcl='enable_central_service_config = true' \
  -hcl='performance { raft_multiplier = ${var.raft_multiplier} }' \
  -hcl='leave_on_terminate = true' \
%{if var.tls~}
  -hcl='tls { defaults { ca_file = "/consul/consul-agent-ca.pem" }}' \
  -hcl='tls { defaults { cert_file = "/consul/${var.datacenter}-server-consul-0.pem" }}' \
  -hcl='tls { defaults { key_file = "/consul/${var.datacenter}-server-consul-0-key.pem" }}' \
  -hcl='tls { defaults { verify_incoming = true, verify_outgoing = true }}' \
  -hcl='tls { internal_rpc { verify_server_hostname = true }}' \
  -hcl='auto_encrypt = {allow_tls = true}' \
  -hcl='ports { server = 8300, serf_lan = 8301, serf_wan = 8302, https = 8501, grpc = 8502, grpc_tls = 8503 }' \
%{endif~}
%{if var.acls~}
  -hcl='acl {enabled = true, default_policy = "deny", down_policy = "extend-cache", enable_token_persistence = true}' \
  -hcl='acl = { tokens = { initial_management = "${local.bootstrap_token}", default = "${local.bootstrap_token}" }}' \
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
%{if var.aws_auto_join~}
  -retry-join "provider=aws tag_key=Consul-Auto-Join tag_value=${var.name} service=ecs" \
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
  // Generate consul_count server configurations.
  // The index of the range iteration is specified multiple times to be used the same number of times in the template.
  //consul_server_commands = [for i in range(var.consul_count) : format(local.consul_server_command_template, i)]

  // We use this command to generate the server certs dynamically before the servers start
  // because we need to add the IP of the task as a SAN to the certificate, and we don't know that
  // IP ahead of time.
  consul_server_tls_init_command_template = <<EOF
ECS_IPV4=$(curl -s $ECS_CONTAINER_METADATA_URI_V4 | jq -r '.Networks[0].IPv4Addresses[0]')
cd /consul
echo "$CONSUL_CACERT_PEM" > ./consul-agent-ca.pem
echo "$CONSUL_CAKEY" > ./consul-agent-ca-key.pem
consul tls cert create -server \
  -node="${local.node_name}%s" \
  -dc="${var.datacenter}" \
  -additional-ipaddress=$ECS_IPV4 \
  -additional-dnsname="${var.name}%s.${local.service_discovery_namespace}" \
%{if length(var.additional_dns_names) > 0~}
  %{for dnsname in var.additional_dns_names~}
    -additional-dnsname="${dnsname}" \
  %{endfor~}
%{endif~}
EOF

  consul_portmap = [{
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
  datadog_portmap = [{
    containerPort : 8125,
    hostPort : 8125,
    protocol : "udp"
  }]

  use_docker_credentials = length(compact([var.docker_username, var.docker_password])) == 2 ? true : false
}

# ---------------------------------------------------------------------------------------------------------------------
# Create TLS, Enterprise License, Bootstrap Token and Gossip-Key Secrets
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "certs" {
  for_each                = local.certs
  name                    = "${lower(var.name)}/${lower(var.datacenter)}/tls/${each.key}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "certs" {
  for_each      = local.certs
  secret_id     = aws_secretsmanager_secret.certs[each.key].id
  secret_string = templatefile("${path.root}/${each.value}", {})
}

// Optional Enterprise license.
resource "aws_secretsmanager_secret" "license" {
  count                   = local.consul_enterprise_enabled ? 1 : 0
  name                    = "${lower(var.name)}/${lower(var.datacenter)}/consul-license"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "license" {
  count         = local.consul_enterprise_enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.license[count.index].id
  secret_string = chomp(var.consul_license) // trim trailing newlines
}

resource "random_uuid" "bootstrap_token" {
  count = local.generate_bootstrap_token ? 1 : 0
}

resource "aws_secretsmanager_secret" "bootstrap_token" {
  count                   = local.generate_bootstrap_token ? 1 : 0
  name                    = "${lower(var.name)}/${lower(var.datacenter)}/bootstrap-token"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "bootstrap_token" {
  count         = local.generate_bootstrap_token ? 1 : 0
  secret_id     = aws_secretsmanager_secret.bootstrap_token[0].id
  secret_string = local.bootstrap_token
}

resource "random_id" "gossip_key" {
  count       = local.generate_gossip_key ? 1 : 0
  byte_length = 32
}

resource "aws_secretsmanager_secret" "gossip_key" {
  count                   = local.generate_gossip_key ? 1 : 0
  name                    = "${lower(var.name)}/${lower(var.datacenter)}/gossip-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "gossip_key" {
  count         = local.generate_gossip_key ? 1 : 0
  secret_id     = aws_secretsmanager_secret.gossip_key[count.index].id
  secret_string = random_id.gossip_key[count.index].b64_std
}

resource "aws_secretsmanager_secret" "datadog_apikey" {
  count                   = var.datadog_apikey == "" ? 0 : 1
  name                    = "${lower(var.name)}/${lower(var.datacenter)}/datadog_apikey"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "datadog_apikey" {
  count         = var.datadog_apikey == "" ? 0 : 1
  secret_id     = aws_secretsmanager_secret.datadog_apikey[0].id
  secret_string = var.datadog_apikey
}

resource "aws_secretsmanager_secret" "docker_key" {
  count                   = local.use_docker_credentials ? 1 : 1
  name                    = "${lower(var.name)}/${lower(var.datacenter)}/docker_key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "docker_key" {
  count     = local.use_docker_credentials ? 1 : 0
  secret_id = aws_secretsmanager_secret.docker_key[0].id
  secret_string = jsonencode({
    username : var.docker_username
    password : var.docker_password
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Create the EFS Cluster
# ---------------------------------------------------------------------------------------------------------------------

module "consul-server-efs-cluster" {
  source = "../efs-cluster"

  name   = "${title(var.name)}FS"
  count  = var.deploy_efs_cluster ? 1 : 0
  vpc_id = var.vpc_id

  access_point_config = { for k, v in local.server_map : k => {
    owner_gid : v["owner_gid"]
    owner_uid : v["owner_uid"]
    permissions : v["permissions"]
    subnet_id : var.private_subnet_ids[v["index"]]
  } }
}

resource "aws_cloudwatch_dashboard" "consul-ecs-efs" {
  count          = var.deploy_efs_cluster ? 1 : 0
  dashboard_name = "${var.name}Dashboard"
  dashboard_body = templatefile("${path.module}/templates/consul-ecs-efs-dashboard.json.j2", {
    aws_region : data.aws_region.current.name
    cluster_name : var.ecs_cluster_name
    efs_filesystem_id : module.consul-server-efs-cluster[0].efs_id
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Create the Consul Server ECS Service, Tasks & IAM
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "container-logs" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.ecs_log_retention_period
}

module "consul-server" {
  source   = "../ecs-service"
  for_each = local.server_map

  name             = title(each.key)
  ecs_cluster_name = var.ecs_cluster_name
  subnet_ids       = [each.value["subnet_id"]]
  vpc_id           = var.vpc_id

  # health_check_grace_period_seconds  = 90
  # Force ecs to retire the old container before the new one is started
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0
  # deployment_circuit_breaker_enable  = true
  target_groups = {
    consul8501 : {
      protocol : "TCP"
      port : 8500
      arn : aws_lb_target_group.this[each.key].arn
    }
  }
  service_registries = [{
    registry_arn   = aws_service_discovery_service.server.arn
    container_name = "consul-server"
  }]
  container_name = "consul-server"
  sidecar_name   = var.datadog_apikey == "" ? null : "datadog"
  cpu            = var.consul_container_cpu
  memory         = var.consul_container_memory

  cpu_architecture        = var.cpu_architecture
  operating_system_family = var.operating_system_family

  tags = {
    "Consul-Auto-Join" : var.name
  }

  task_definition = concat(each.value["init"], [
    {
      name : "consul-server"
      image : var.consul_image
      repositoryCredentials : local.use_docker_credentials ? {
        credentialsParameter : aws_secretsmanager_secret.docker_key[0].arn
      } : null
      cpu : var.consul_task_cpu
      memory : var.consul_task_memory
      essential : true
      entryPoint : ["/bin/sh", "-ec"]
      command : [replace(each.value["command"], "\r", "")]
      linuxParameters : {
        initProcessEnabled : true
      }
      dependsOn = var.tls ? [
        {
          containerName = "tls-init"
          condition     = "SUCCESS"
        },
      ] : []
      portMappings : local.consul_portmap
      volumesFrom : []
      mountPoints : var.deploy_efs_cluster ? [
        {
          containerPath : "/consul"
          sourceVolume : each.key
          readOnly : false
        }
      ] : []
      secrets : concat(
        var.gossip_encryption_enabled ? [
          {
            name      = "CONSUL_GOSSIP_ENCRYPTION_KEY"
            valueFrom = local.gossip_key_arn
          },
        ] : [],
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
          awslogs-group : aws_cloudwatch_log_group.container-logs.name,
          awslogs-region : data.aws_region.current.name,
          awslogs-stream-prefix : "consul"
        }
      }
    }
    ], var.datadog_apikey == "" ? [] : [{
      name : "datadog"
      image : "public.ecr.aws/datadog/agent:7"
      cpu : var.datadog_task_cpu
      memory : var.datadog_task_memory
      essential : false
      portMappings : local.datadog_portmap
      environment : [
        {
          name : "ECS_FARGATE"
          value : "true"
        },
        {
          name : "DD_DOGSTATSD_NON_LOCAL_TRAFFIC"
          value : "true"
        },
      ]
      volumesFrom : []
      mountPoints : []
      secrets : [
        {
          name : "DD_API_KEY",
          valueFrom : aws_secretsmanager_secret.datadog_apikey[0].arn
        }
      ]
      healthCheck : {
        retries : 3,
        command : ["CMD-SHELL", "agent health"],
        timeout : 5,
        interval : 30,
        startPeriod : 15,
      }
      logConfiguration : {
        logDriver : "awslogs",
        options : {
          awslogs-group : aws_cloudwatch_log_group.container-logs.name,
          awslogs-region : data.aws_region.current.name,
          awslogs-stream-prefix : "datadog"
        }
      }
    }
  ])
  efs_volumes = var.deploy_efs_cluster ? {
    (each.key) : {
      file_system_id : module.consul-server-efs-cluster[0].efs_id
      access_point_id : module.consul-server-efs-cluster[0].access_point_ids[each.value["index"]]
      root_directory : "/"
      transit_encryption : "ENABLED"
      encryption_port : 2049
      iam : "DISABLED"
    }
  } : {}
  security_group_ids = compact([
    aws_security_group.ecs_service.id,
    var.deploy_efs_cluster ? module.consul-server-efs-cluster[0].efs_client_security_group_id : null,
  ])
  ecs_execution_role_arn = aws_iam_role.this_execution.arn
  ecs_task_role_arn      = aws_iam_role.this_task.arn
  ecs_task_role_id       = aws_iam_role.this_task.id

  depends_on = [
    aws_lb_target_group.this
  ]
}

resource "aws_iam_policy" "this_execution" {
  name        = "${var.name}_execution"
  path        = "/ecs/"
  description = "Consul server execution"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": [
        "${data.aws_kms_alias.secretsmanager.arn}",
        "${data.aws_kms_alias.secretsmanager.target_key_arn}"
      ]
    },
%{if var.tls~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${lower(var.name)}/${lower(var.datacenter)}/tls/*"
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
%{if var.gossip_encryption_enabled~}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${local.gossip_key_arn}"
      ]
    },
%{endif~}
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": ["*"]
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
        },
        {
          Effect = "Allow"
          Action = [
            "elasticfilesystem:ClientMount",
            "elasticfilesystem:ClientWrite",
            "elasticfilesystem:ClientRootAccess",
          ]
          Resource = [
            module.consul-server-efs-cluster[0].efs_arn
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "ecs:ListClusters",
            "ecs:ListServices",
            "ecs:DescribeServices",
            "ecs:ListTasks",
            "ecs:DescribeTasks",
            "ecs:ListContainerInstances",
            "ecs:DescribeContainerInstances",
            "ec2:DescribeNetworkInterfaces",
          ]
          Resource = "*"
        },
      ]
    })
  }
}

#data "aws_iam_policy_document" "ecs_efs_access" {
#  count = var.deploy_efs_cluster ? 1 : 0
#  statement {
#    sid    = "${title(replace(var.name, "-", ""))}EfsAccess"
#    effect = "Allow"
#    actions = [
#      "elasticfilesystem:ClientMount",
#      "elasticfilesystem:ClientWrite",
#      "elasticfilesystem:ClientRootAccess",
#    ]
#    resources = [
#      module.consul-server-efs-cluster[0].efs_arn
#    ]
#  }
#}
#
#resource "aws_iam_role_policy" "ecs_efs_access" {
#  count  = var.deploy_efs_cluster ? 1 : 0
#  name   = "${title(replace(var.name, "-", ""))}EfsAccess"
#  policy = data.aws_iam_policy_document.ecs_efs_access[0].json
#  role   = aws_iam_role.this_task.id
#}
#
#data "aws_iam_policy_document" "ecs_auto_discover" {
#  statement {
#    sid    = "${title(replace(var.name, "-", ""))}AutoDiscover"
#    effect = "Allow"
#    actions = [
#      "ecs:ListClusters",
#      "ecs:ListServices",
#      "ecs:DescribeServices",
#      "ecs:ListTasks",
#      "ecs:DescribeTasks",
#      "ecs:DescribeContainerInstances",
#      "ec2:DescribeNetworkInterfaces",
#    ]
#    resources = ["*"]
#  }
#}
#
#resource "aws_iam_role_policy" "ecs_auto_discover" {
#  name   = "${title(replace(var.name, "-", ""))}AutoDiscover"
#  policy = data.aws_iam_policy_document.ecs_auto_discover.json
#  role   = aws_iam_role.this_task.id
#}
#
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
#  policy = data.aws_iam_policy_document.ecs_auto_discover.json
#  role   = aws_iam_role.this_task.id
#}

# ---------------------------------------------------------------------------------------------------------------------
# Add Consul to AWS Service Discovery
# ---------------------------------------------------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------------------------------------------------
# ALB & Security Groups
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lb" "this" {
  count              = var.lb_enabled ? 1 : 0
  name               = var.name
  internal           = var.internal_alb_listener
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load_balancer[0].id]
  #subnets            = var.internal_alb_listener ? var.private_subnet_ids : var.public_subnet_ids

  access_logs {
    enabled = false
    bucket  = ""
  }

  dynamic "subnet_mapping" {
    for_each = var.internal_alb_listener ? var.private_subnet_ids : var.public_subnet_ids
    content {
      subnet_id  = subnet_mapping.value
      outpost_id = null
    }
  }

  tags = {}
}

resource "aws_iam_server_certificate" "alb-cert" {
  count            = var.lb_enabled ? 1 : 0
  name             = "${var.name}_alb_certificate"
  certificate_body = aws_secretsmanager_secret_version.certs["CONSUL_ALB_CERT"].secret_string
  private_key      = aws_secretsmanager_secret_version.certs["CONSUL_ALB_KEY"].secret_string
}

resource "aws_lb_target_group" "this" {
  for_each    = var.lb_enabled ? local.server_map : {}
  name        = title(each.key)
  port        = 8500
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

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

resource "aws_lb_listener" "this" {
  count             = var.lb_enabled ? 1 : 0
  load_balancer_arn = aws_lb.this[0].arn
  port              = "8501"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-2019-08"
  certificate_arn   = aws_iam_server_certificate.alb-cert[0].arn

  default_action {
    type = "forward"
    forward {
      dynamic "target_group" {
        for_each = aws_lb_target_group.this
        content {
          arn = aws_lb_target_group.this[target_group.key].arn
        }
      }
    }
  }
  depends_on = [
    aws_iam_server_certificate.alb-cert
  ]
}

resource "aws_security_group" "load_balancer" {
  count  = var.lb_enabled ? 1 : 0
  name   = "${var.name}-lb-sg"
  vpc_id = var.vpc_id

  ingress {
    description     = "Access to Consul dev server HTTP API and UI."
    from_port       = 8500
    to_port         = 8501
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

resource "aws_security_group_rule" "ecs_service_self" {
  description       = "Allow Consul Servers to speak with each other on all ports and protocols."
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.ecs_service.id
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

