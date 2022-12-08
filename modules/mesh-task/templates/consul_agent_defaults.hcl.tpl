addresses = {
  dns = "127.0.0.1"
  grpc = "127.0.0.1"
  http = "127.0.0.1"
}
advertise_addr = "$ECS_IPV4"
advertise_reconnect_timeout = "15m"
client_addr = "0.0.0.0"
datacenter = "$CONSUL_DATACENTER"
enable_central_service_config = true
%{ if gossip_encryption_enabled ~}
encrypt = "$CONSUL_GOSSIP_ENCRYPTION_KEY"
%{ endif ~}
leave_on_terminate = true
ports {
  grpc = 8502
}
retry_join = [
%{ for j in retry_join ~}
  "${j}",
%{ endfor ~}
]

%{~ if tls ~}
auto_encrypt = {
  tls = true
  ip_san = ["$ECS_IPV4"]
}
ca_file = "/consul/consul-ca-cert.pem"
verify_outgoing = true
%{ endif ~}

%{~ if acls ~}
acl {
  enabled = true
  default_policy = "deny"
  down_policy = "async-cache"
  tokens {
    agent = "$AGENT_TOKEN"
  }
  enable_token_replication = ${enable_token_replication}
}
%{ endif ~}

%{ if partition != null && partition != "" ~}
partition = "${partition}"
%{ endif ~}

%{ if primary_datacenter != "" ~}
primary_datacenter = "${primary_datacenter}"
%{ endif ~}

%{~ if audit_logging ~}
audit {
  enabled = true
  sink "stdout" {
    type   = "file"
    format = "json"
    path   = "/dev/stdout"
    delivery_guarantee = "best-effort"
  }
}
%{ endif ~}
