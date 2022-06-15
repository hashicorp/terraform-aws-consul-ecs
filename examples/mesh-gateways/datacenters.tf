locals {
  primary_datacenter   = var.datacenter_names[0]
  secondary_datacenter = var.datacenter_names[1]
}

module "dc1" {
  source = "./datacenter"

  name            = "${var.name}-${local.primary_datacenter}"
  datacenter      = local.primary_datacenter
  lb_ingress_ip   = var.lb_ingress_ip
  private_subnets = module.dc1_vpc.private_subnets
  public_subnets  = module.dc1_vpc.public_subnets
  region          = var.region
  vpc             = module.dc1_vpc

  // To enable WAN federation via mesh gateways both servers must be configured with:
  // - The same primary datacenter.
  // - The same CA private key and certificate.
  // - The same gossip encryption key.
  // - The flag `enable_mesh_gateway_wan_federation` set to true. See https://www.consul.io/docs/connect/gateways/mesh-gateway/wan-federation-via-mesh-gateways#consul-server-options.
  primary_datacenter                 = local.primary_datacenter
  ca_cert_arn                        = aws_secretsmanager_secret.ca_cert.arn
  ca_key_arn                         = aws_secretsmanager_secret.ca_key.arn
  gossip_key_arn                     = aws_secretsmanager_secret.gossip_key.arn
  enable_mesh_gateway_wan_federation = true

  bootstrap_token_arn = aws_secretsmanager_secret.bootstrap_token.arn
  bootstrap_token     = random_uuid.bootstrap_token.result

  consul_ecs_image = var.consul_ecs_image
}

module "dc2" {
  source = "./datacenter"

  name            = "${var.name}-${local.secondary_datacenter}"
  datacenter      = local.secondary_datacenter
  lb_ingress_ip   = var.lb_ingress_ip
  private_subnets = module.dc2_vpc.private_subnets
  public_subnets  = module.dc2_vpc.public_subnets
  region          = var.region
  vpc             = module.dc2_vpc

  primary_datacenter                 = local.primary_datacenter
  ca_cert_arn                        = aws_secretsmanager_secret.ca_cert.arn
  ca_key_arn                         = aws_secretsmanager_secret.ca_key.arn
  gossip_key_arn                     = aws_secretsmanager_secret.gossip_key.arn
  enable_mesh_gateway_wan_federation = true

  // To enable WAN federation via mesh gateways all secondary datacenters must be
  // configured with the WAN address of the mesh gateway(s) in the primary datacenter.
  primary_gateways = ["${module.dc1_gateway.wan_address}:${module.dc1_gateway.wan_port}"]

  // To enable ACL replication for secondary datacenters we need to provide a replication token.
  bootstrap_token_arn = aws_secretsmanager_secret.bootstrap_token.arn
  bootstrap_token     = random_uuid.bootstrap_token.result

  // TODO this should be a replication token with only the necessary ACL policies.
  // See https://www.consul.io/docs/security/acl/acl-federated-datacenters#create-the-replication-token-for-acl-management
  replication_token = random_uuid.bootstrap_token.result

  consul_ecs_image = var.consul_ecs_image
}

// Create a null_resource that will wait for the Consul server to be available via its ALB.
// This allows us to wait until the Consul server is reachable before trying to create
// Consul resources like config entries. If we don't wait, Terraform will fail to create
// the necessary Consul resources.
resource "null_resource" "wait_for_primary_consul_server" {
  depends_on = [module.dc1]
  triggers = {
    // Trigger update when Consul server ALB DNS name changes.
    consul_server_lb_dns_name = "${module.dc1.dev_consul_server.lb_dns_name}"
  }
  provisioner "local-exec" {
    command = <<EOT
stopTime=$(($(date +%s) + ${var.consul_server_startup_timeout})) ; \
while [ $(date +%s) -lt $stopTime ] ; do \
  sleep 10 ; \
  statusCode=$(curl -s -o /dev/null -w '%%{http_code}' http://${module.dc1.dev_consul_server.lb_dns_name}:8500/v1/catalog/services)
  [ $statusCode -eq 200 ] && break; \
done
EOT
  }
}

// Create an intention to allow the example client to call the example server
resource "consul_config_entry" "service_intention" {
  kind = "service-intentions"
  name = local.example_server_app_name

  config_json = jsonencode({
    Sources = [
      {
        Name       = local.example_client_app_name
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      }
    ]
  })
  depends_on = [null_resource.wait_for_primary_consul_server]
}

resource "random_uuid" "bootstrap_token" {}

resource "aws_secretsmanager_secret" "bootstrap_token" {
  name                    = "${var.name}-bootstrap-token-shared"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "bootstrap_token" {
  secret_id     = aws_secretsmanager_secret.bootstrap_token.id
  secret_string = random_uuid.bootstrap_token.result
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
