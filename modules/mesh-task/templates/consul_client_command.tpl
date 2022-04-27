cp /bin/consul /bin/consul-inject/consul

ECS_TASK_META=$(curl -s $ECS_CONTAINER_METADATA_URI_V4)
ECS_IPV4=$(echo "$ECS_TASK_META" | jq -r '.Networks[0].IPv4Addresses[0]')
TASK_REGION=$(echo "$ECS_TASK_META" | jq -r .ContainerARN | cut -d':' -f4)

%{ if tls ~}
echo "$CONSUL_CACERT" > /consul/consul-ca-cert.pem
%{ endif ~}

%{ if acls && client_token_auth_method_name != "" ~}

login() {
    echo "Logging into auth method: name=${ client_token_auth_method_name }"
    consul login \
      -http-addr ${ consul_http_addr } \
    %{ if tls ~}
      -ca-file /consul/consul-ca-cert.pem \
    %{ endif ~}
    %{ if consul_partition != "" ~}
      -partition ${ consul_partition } \
    %{ endif ~}
      -type aws -method ${ client_token_auth_method_name } \
      -aws-region "$TASK_REGION" \
      -aws-auto-bearer-token -aws-include-entity \
      -token-sink-file /consul/client-token
}

while ! login; do
    sleep 2
done

# This is an env var which is interpolated into the agent-defaults.hcl
export AGENT_TOKEN=$(cat /consul/client-token)
%{ endif ~}

cat << EOF > /consul/agent-defaults.hcl
${consul_agent_defaults_hcl}
EOF

%{ if consul_agent_configuration_hcl != "" ~}
cat << EOF > /consul/agent-extra.hcl
${consul_agent_configuration_hcl}
EOF
%{ endif ~}

exec consul agent \
    -data-dir /consul/data \
    -config-file /consul/agent-defaults.hcl \
%{ if consul_agent_configuration_hcl != "" ~}
    -config-file /consul/agent-extra.hcl
%{ endif ~}
