# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# generate ca cert and key for tgw <-> external app communication
resource "tls_private_key" "external_app_ca_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "external_app_ca_cert" {
  private_key_pem       = tls_private_key.external_app_ca_key.private_key_pem
  validity_period_hours = 43800
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "cert_signing",
    "crl_signing",
    "client_auth",
  ]
  dns_names = ["*"]
  subject {
    common_name  = "*"
    organization = "HashiCorp Inc."
  }

  is_ca_certificate  = true
  set_subject_key_id = true
}

resource "aws_secretsmanager_secret" "external_app_ca_key" {
  name                    = "${var.name}-external-app-ca-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "external_app_ca_key" {
  secret_id     = aws_secretsmanager_secret.external_app_ca_key.id
  secret_string = tls_private_key.external_app_ca_key.private_key_pem
}

resource "aws_secretsmanager_secret" "external_app_ca_cert" {
  name                    = "${var.name}-external-app-ca-cert"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "external_app_ca_cert" {
  secret_id     = aws_secretsmanager_secret.external_app_ca_cert.id
  secret_string = tls_self_signed_cert.external_app_ca_cert.cert_pem
}

# generate cert and key for the external app
resource "tls_private_key" "external_app_private_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "csr_external_app" {

  private_key_pem = tls_private_key.external_app_private_key.private_key_pem

  dns_names = ["*"]

  subject {
    common_name  = "*"
    organization = "HashiCorp Inc."
  }
}

resource "tls_locally_signed_cert" "external_app_cert" {
  validity_period_hours = 168
  early_renewal_hours   = 24
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]

  // CSR by the development servers
  cert_request_pem = tls_cert_request.csr_external_app.cert_request_pem
  // CA Private key
  ca_private_key_pem = tls_private_key.external_app_ca_key.private_key_pem
  // CA certificate
  ca_cert_pem = tls_self_signed_cert.external_app_ca_cert.cert_pem
}

resource "aws_secretsmanager_secret" "external_app_private_key" {
  name                    = "${var.name}-external-private-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "external_private_key" {
  secret_id     = aws_secretsmanager_secret.external_app_private_key.id
  secret_string = tls_private_key.external_app_private_key.private_key_pem
}

resource "aws_secretsmanager_secret" "external_cert" {
  name                    = "${var.name}-external-cert"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "external_cert" {
  secret_id     = aws_secretsmanager_secret.external_cert.id
  secret_string = tls_locally_signed_cert.external_app_cert.cert_pem
}

# generate cert and key for the gateway
resource "tls_private_key" "tgw_private_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "csr_tgw" {

  private_key_pem = tls_private_key.tgw_private_key.private_key_pem

  dns_names = ["*"]

  subject {
    common_name  = "*"
    organization = "HashiCorp Inc."
  }
}

resource "tls_locally_signed_cert" "tgw_cert" {
  validity_period_hours = 168
  early_renewal_hours   = 24
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]

  // CSR by the development servers
  cert_request_pem = tls_cert_request.csr_tgw.cert_request_pem
  // CA Private key
  ca_private_key_pem = tls_private_key.external_app_ca_key.private_key_pem
  // CA certificate
  ca_cert_pem = tls_self_signed_cert.external_app_ca_cert.cert_pem
}

resource "aws_secretsmanager_secret" "tgw_private_key" {
  name                    = "${var.name}-tgw-private-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "tgw_private_key" {
  secret_id     = aws_secretsmanager_secret.tgw_private_key.id
  secret_string = tls_private_key.tgw_private_key.private_key_pem
}

resource "aws_secretsmanager_secret" "tgw_cert" {
  name                    = "${var.name}-tgw-cert"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "tgw_cert" {
  secret_id     = aws_secretsmanager_secret.tgw_cert.id
  secret_string = tls_locally_signed_cert.tgw_cert.cert_pem
}