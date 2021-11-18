cp /bin/consul /bin/consul-inject/consul

ECS_IPV4=$(curl -s $ECS_CONTAINER_METADATA_URI_V4 | jq -r '.Networks[0].IPv4Addresses[0]')

%{ if tls }
echo "$CONSUL_CACERT" > /tmp/consul-ca-cert.pem
%{ endif }

exec consul agent \
  -advertise "$ECS_IPV4" \
  -datacenter "$CONSUL_DATACENTER" \
  -data-dir /consul/data \
  -client 0.0.0.0 \
  -hcl 'telemetry { dogstatsd_addr = "127.0.0.1:8125" }' \
%{ if gossip_encryption_enabled ~}
  -encrypt "$CONSUL_GOSSIP_ENCRYPTION_KEY" \
%{ endif ~}
  -hcl 'addresses = { dns = "127.0.0.1" }' \
  -hcl 'addresses = { grpc = "127.0.0.1" }' \
  -hcl 'addresses = { http = "127.0.0.1" }' \
%{ for j in retry_join ~}
  -retry-join "${j}" \
%{ endfor ~}
  -hcl 'telemetry { disable_compat_1.9 = true }' \
  -hcl 'leave_on_terminate = true' \
  -hcl 'ports { grpc = 8502 }' \
  -hcl 'advertise_reconnect_timeout = "15m"' \
  -hcl 'enable_central_service_config = true' \
%{ if tls ~}
  -hcl 'ca_file = "/tmp/consul-ca-cert.pem"' \
  -hcl 'auto_encrypt = {tls = true}' \
  -hcl "auto_encrypt = {ip_san = [\"$ECS_IPV4\"]}" \
  -hcl 'verify_outgoing = true' \
  -hcl 'verify_incoming = true' \
%{ endif ~}
%{ if acls ~}
  -hcl='acl {enabled = true, default_policy = "deny", down_policy = "async-cache"}' \
  -hcl="acl { tokens { agent = \"$AGENT_TOKEN\" } }" \
%{ endif ~}
