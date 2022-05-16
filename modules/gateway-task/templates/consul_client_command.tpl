cp /bin/consul /bin/consul-inject/consul

ECS_IPV4=$(curl -s $ECS_CONTAINER_METADATA_URI_V4 | jq -r '.Networks[0].IPv4Addresses[0]')

%{ if tls ~}
echo "$CONSUL_CACERT" > /tmp/consul-ca-cert.pem
%{ endif ~}

cat << EOF > /consul/agent-defaults.hcl
${consul_agent_defaults_hcl}
EOF

%{ if consul_agent_configuration_hcl != null ~}
cat << EOF > /consul/agent-extra.hcl
${consul_agent_configuration_hcl}
EOF
%{ endif ~}

exec consul agent \
    -data-dir /consul/data \
    -config-file /consul/agent-defaults.hcl \
%{ if consul_agent_configuration_hcl != null ~}
    -config-file /consul/agent-extra.hcl
%{ endif ~}
