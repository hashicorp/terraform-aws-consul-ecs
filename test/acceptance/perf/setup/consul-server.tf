data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "random_id" "gossip_encryption_key" {
  byte_length = 32
}

resource "random_string" "secret_suffix" {
  length  = 7
  special = false
}

resource "tls_private_key" "ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "ca" {
  key_algorithm   = "ECDSA"
  private_key_pem = tls_private_key.ca.private_key_pem

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

resource "tls_private_key" "server_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_cert_request" "server_csr" {
  key_algorithm   = "ECDSA"
  private_key_pem = tls_private_key.server_key.private_key_pem

  dns_names = [
    "localhost",
    "server.dc1.consul",
    "*.server.dc1.consul",
  ]

  ip_addresses = ["127.0.0.1"]

  subject {
    common_name  = "consul"
    organization = "HashiCorp"
  }
}

resource "tls_locally_signed_cert" "server_cert" {
  cert_request_pem   = tls_cert_request.server_csr.cert_request_pem
  ca_key_algorithm   = "ECDSA"
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]
}

resource "aws_secretsmanager_secret" "ca_key" {
  name                    = "${local.name}-ca-key-${random_string.secret_suffix.result}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "ca_key" {
  secret_id     = aws_secretsmanager_secret.ca_key.id
  secret_string = tls_private_key.ca.private_key_pem
}

resource "aws_secretsmanager_secret" "ca_cert" {
  name                    = "${local.name}-ca-cert-${random_string.secret_suffix.result}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "ca_cert" {
  secret_id     = aws_secretsmanager_secret.ca_cert.id
  secret_string = tls_self_signed_cert.ca.cert_pem
}

resource "aws_secretsmanager_secret" "gossip_key" {
  name                    = "${local.name}-gossip-encryption-key-${random_string.secret_suffix.result}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "gossip_key" {
  secret_id     = aws_secretsmanager_secret.gossip_key.id
  secret_string = random_id.gossip_encryption_key.b64_std
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "aws_key_pair" "key_pair" {
  key_name   = "${local.name}-${random_string.secret_suffix.result}"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "null_resource" "save_key" {
  triggers = {
    key = tls_private_key.ssh.private_key_pem
  }

  provisioner "local-exec" {
    command = <<EOF
      mkdir -p ${path.module}/.ssh
      echo "${tls_private_key.ssh.private_key_pem}" > ${path.module}/.ssh/id_rsa
      chmod 0600 ${path.module}/.ssh/id_rsa
EOF
  }
}

# Create an IAM policy for allowing instances that are running
# Consul agent can use to list the consul servers.
resource "aws_iam_policy" "consul_retry_join" {
  name        = "${local.name}-consul-retry-join"
  description = "Allows Consul nodes to describe instances for joining."

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:DescribeInstances",
      "Resource": "*"
    }
  ]
}
EOF
}

# Create an IAM role for the auto-join
resource "aws_iam_role" "consul_retry_join" {
  name = "${local.name}-consul-retry-join"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Attach the policy
resource "aws_iam_role_policy_attachment" "consul_retry_join" {
  role       = aws_iam_role.consul_retry_join.name
  policy_arn = aws_iam_policy.consul_retry_join.arn
}

# Create the instance profile
resource "aws_iam_instance_profile" "consul_retry_join" {
  name = "${local.name}-consul-retry-join"
  role = aws_iam_role.consul_retry_join.name
}

resource "random_uuid" "bootstrap_token" {}

resource "aws_secretsmanager_secret" "bootstrap_token" {
  name                    = "${local.name}-bootstrap-token-${random_string.secret_suffix.result}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "bootstrap_token" {
  secret_id     = aws_secretsmanager_secret.bootstrap_token.id
  secret_string = random_uuid.bootstrap_token.result
}

module "consul-server" {
  // https://github.com/hashicorp/consul-global-scale-benchmark doesn't support ACLs so I forked it
  source               = "github.com/erichaberkorn/consul-global-scale-benchmark/infrastructure/consul-server-ec2"
  project              = local.name
  vpc_id               = module.vpc.vpc_id
  private_subnets      = module.vpc.private_subnets
  public_subnets       = module.vpc.public_subnets
  consul_version       = "1.10.2"
  region               = var.region
  datadog_api_key      = var.datadog_api_key
  consul_download_url  = "" // We need to provide it as it is a required variable.
  retry_join_tag       = local.name
  ami_id               = data.aws_ami.ubuntu.id
  iam_instance_profile = aws_iam_instance_profile.consul_retry_join.name

  key_name = aws_key_pair.key_pair.key_name

  gossip_encryption_key = random_id.gossip_encryption_key.b64_std
  tls_ca_cert_pem       = tls_self_signed_cert.ca.cert_pem
  tls_server_cert_pem   = tls_locally_signed_cert.server_cert.cert_pem
  tls_server_key_pem    = tls_private_key.server_key.private_key_pem
  bootstrap_token       = random_uuid.bootstrap_token.result
  enable_streaming      = true
  lb_ingress_ip         = var.lb_ingress_ip
}

provider "consul" {
  address = "${module.consul-server.consul_elb}:80"
  token   = random_uuid.bootstrap_token.result
}
