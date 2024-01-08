resource "aws_security_group" "efs" {
  name        = "efs-sg"
  description = "Allows inbound efs traffic from ec2"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "certs_efs" {
  creation_token   = "certs-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = "true"
  tags = {
    Name = "Certs"
  }
}


resource "aws_efs_mount_target" "efs_mt" {
  count           = length(module.vpc.private_subnets)
  file_system_id  = aws_efs_file_system.certs_efs.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

#############################################################

# generate ca cert and key
resource "tls_private_key" "tgw_external_app_ca_key" {
  algorithm = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "tgw_external_app_ca_cert" {
  private_key_pem = tls_private_key.tgw_external_app_ca_key.private_key_pem
  validity_period_hours = 43800
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "cert_signing",
    "crl_signing",
  ]
  dns_names = ["*"]
  subject {
    common_name  = "*"
    organization = "HashiCorp Inc."
  }

  is_ca_certificate  = true
  set_subject_key_id = true
}

resource "aws_secretsmanager_secret" "tgw_external_app_ca_key" {
  name                    = "tgw-external-app-ca-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "tgw_external_app_ca_key" {
  secret_id     = aws_secretsmanager_secret.tgw_external_app_ca_key.id
  secret_string = tls_private_key.tgw_external_app_ca_key.private_key_pem
}

resource "aws_secretsmanager_secret" "tgw_external_app_ca_cert" {
  name                    = "tgw-external-app-ca-cert"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "tgw_external_app_ca_cert" {
  secret_id     = aws_secretsmanager_secret.tgw_external_app_ca_cert.id
  secret_string = tls_self_signed_cert.tgw_external_app_ca_cert.cert_pem
}

#generate cert and key for the gateway
resource "tls_private_key" "tgw_external_app_private_key" {
  algorithm = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "csr" {

  private_key_pem = tls_private_key.tgw_external_app_private_key.private_key_pem

  dns_names = ["*"]

  subject {
    common_name  = "*"
    organization = "HashiCorp Inc."
  }
}

resource "tls_locally_signed_cert" "tgw_external_app_cert" {
  validity_period_hours = 168
  early_renewal_hours = 24
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]

  // CSR by the development servers
  cert_request_pem = tls_cert_request.csr.cert_request_pem
  // CA Private key
  ca_private_key_pem = tls_private_key.tgw_external_app_ca_key.private_key_pem
  // CA certificate
  ca_cert_pem = tls_self_signed_cert.tgw_external_app_ca_cert.cert_pem
}

resource "aws_secretsmanager_secret" "tgw_external_app_key" {
  name                    = "tgw-external-app-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "tgw_external_app_key" {
  secret_id     = aws_secretsmanager_secret.tgw_external_app_key.id
  secret_string = tls_private_key.tgw_external_app_private_key.private_key_pem
}

resource "aws_secretsmanager_secret" "tgw_external_app_cert" {
  name                    = "tgw-external-app-cert"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "tgw_external_app_cert" {
  secret_id     = aws_secretsmanager_secret.tgw_external_app_cert.id
  secret_string = tls_locally_signed_cert.tgw_external_app_cert.cert_pem
}

#############################################################

