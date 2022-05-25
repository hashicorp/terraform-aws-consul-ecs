locals {
  primary_datacenter  = var.datacenter_names[0]
  primary_node_name   = "${var.name}-${var.datacenter_names[0]}-consul-server.${var.datacenter_names[0]}"
  secondary_node_name = "${var.name}-${var.datacenter_names[1]}-consul.server.${var.datacenter_names[1]}"
}

module "dc1" {
  source = "./datacenter"

  datacenter         = var.datacenter_names[0]
  lb_ingress_ip      = var.lb_ingress_ip
  name               = "${var.name}-${var.datacenter_names[0]}"
  private_subnets    = module.dc1_vpc.private_subnets
  public_subnets     = module.dc1_vpc.public_subnets
  region             = var.region
  vpc                = module.dc1_vpc
  primary_datacenter = local.primary_datacenter
  ca_cert_arn        = aws_secretsmanager_secret.ca_cert.arn
  ca_key_arn         = aws_secretsmanager_secret.ca_key.arn
  gossip_key_arn     = aws_secretsmanager_secret.gossip_key.arn

  // Should be `[module.dc2.dev_consul_server.server_dns]`
  // But that would create a circular dependency. So predict the server name.
  //TODO remove? additional_dns_names = [local.secondary_node_name]

  enable_mesh_gateway_wan_peering = true
  //TODO remove? node_name                       = "primary"
}

module "dc2" {
  source = "./datacenter"

  datacenter         = var.datacenter_names[1]
  lb_ingress_ip      = var.lb_ingress_ip
  name               = "${var.name}-${var.datacenter_names[1]}"
  private_subnets    = module.dc2_vpc.private_subnets
  public_subnets     = module.dc2_vpc.public_subnets
  region             = var.region
  vpc                = module.dc2_vpc
  primary_datacenter = local.primary_datacenter
  primary_gateways   = ["${module.dc1_gateway.lb_dns_name}:8443"]
  ca_cert_arn        = aws_secretsmanager_secret.ca_cert.arn
  ca_key_arn         = aws_secretsmanager_secret.ca_key.arn
  gossip_key_arn     = aws_secretsmanager_secret.gossip_key.arn

  //TODO remove? additional_dns_names = ["${var.name}-${var.datacenter_names[0]}-consul-server.consul-${var.datacenter_names[0]}"]

  enable_mesh_gateway_wan_peering = true
  //TODO remove? node_name                       = "secondary"
}

resource "tls_private_key" "ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "ca" {
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

resource "aws_secretsmanager_secret" "ca_key" {
  name                    = "${var.name}-ca-key-shared"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "ca_key" {
  secret_id     = aws_secretsmanager_secret.ca_key.id
  secret_string = tls_private_key.ca.private_key_pem
}

resource "aws_secretsmanager_secret" "ca_cert" {
  name                    = "${var.name}-ca-cert-shared"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "ca_cert" {
  secret_id     = aws_secretsmanager_secret.ca_cert.id
  secret_string = tls_self_signed_cert.ca.cert_pem
}

resource "random_id" "gossip_key" {
  byte_length = 32
}

resource "aws_secretsmanager_secret" "gossip_key" {
  name                    = "${var.name}-gossip-key-shared"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "gossip_key" {
  secret_id     = aws_secretsmanager_secret.gossip_key.id
  secret_string = random_id.gossip_key.b64_std
}


# // Each Consul server has its own security group that needs to allow traffic from the other.
# resource "aws_security_group_rule" "ingress_from_dc1" {
#   description              = "Access from dc1"
#   type                     = "ingress"
#   from_port                = 0
#   to_port                  = 0
#   protocol                 = "-1"
#   source_security_group_id = module.dc1.dev_consul_server.security_group_id
#   security_group_id        = module.dc2.dev_consul_server.security_group_id
# }

# resource "aws_security_group_rule" "ingress_from_dc2" {
#   description              = "Access from dc2"
#   type                     = "ingress"
#   from_port                = 0
#   to_port                  = 0
#   protocol                 = "-1"
#   source_security_group_id = module.dc2.dev_consul_server.security_group_id
#   security_group_id        = module.dc1.dev_consul_server.security_group_id
# }


// Our app tasks need to allow ingress from the dev-server (in the relevant dc).
// The apps use the default security group so we allow ingress to default from both dev-servers.
resource "aws_security_group_rule" "default_ingress_from_dc1" {
  description              = "Access from dev-server in dc1"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.dc1.dev_consul_server.security_group_id
  security_group_id        = module.dc1_vpc.default_security_group_id
}

resource "aws_security_group_rule" "default_ingress_from_dc2" {
  description              = "Access from dev-server in dc2"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.dc2.dev_consul_server.security_group_id
  security_group_id        = module.dc2_vpc.default_security_group_id
}
