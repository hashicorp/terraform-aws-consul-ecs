cp /bin/consul /bin/consul-inject/consul

ECS_IPV4=$(curl -s $ECS_CONTAINER_METADATA_URI_V4 | jq -r '.Networks[0].IPv4Addresses[0]')

ECS_TASK_META=$(curl -s $ECS_CONTAINER_METADATA_URI_V4/task)
TASK_REGION=$(echo "$ECS_TASK_META" | jq -r .TaskARN | cut -d ':' -f 4)
TASK_ID=$(echo "$ECS_TASK_META" | jq -r .TaskARN | cut -d '/' -f 3)
CLUSTER_ARN=$(echo "$ECS_TASK_META" | jq -r .TaskARN | sed -E 's|:task/([^/]+).*|:cluster/\1|')

%{ if tls ~}
echo "$CONSUL_CACERT_PEM" > /consul/consul-ca-cert.pem
%{ endif ~}

%{ if https ~}
echo "$CONSUL_HTTPS_CACERT_PEM" > /consul/consul-https-ca-cert.pem
%{ endif ~}

%{ if acls ~}
consul_login() {
    echo "Logging into auth method: name=${ client_token_auth_method_name }"
    consul login \
      -http-addr ${ consul_http_addr } \
    %{ if https ~}
      -ca-file /consul/consul-https-ca-cert.pem \
    %{ endif ~}
    %{ if consul_partition != "" ~}
      -partition ${ consul_partition } \
    %{ endif ~}
      -type aws-iam \
      -method ${ client_token_auth_method_name } \
      -meta "consul.hashicorp.com/task-id=$TASK_ID" \
      -meta "consul.hashicorp.com/cluster=$CLUSTER_ARN" \
      -aws-region "$TASK_REGION" \
      -aws-auto-bearer-token -aws-include-entity \
      -token-sink-file /consul/client-token
}

read_token_stale() {
    consul acl token read -http-addr ${ consul_http_addr } \
    %{ if https ~}
      -ca-file /consul/consul-https-ca-cert.pem \
    %{ endif ~}
      -stale -self -token-file /consul/client-token \
      > /dev/null
}

# Retry in order to login successfully.
while ! consul_login; do
    sleep 2
done

# Allow the health-sync container to read this token for consul logout.
# The user here is root, but health-sync runs as a 'consul-ecs' user.
chmod 0644 /consul/client-token

# Wait for raft replication to hopefully occur. Without this, an "ACL not found" may be cached for a while.
# Technically, the problem could still occur but this should handle most cases.
# This waits at most 2s (20 attempts with 0.1s sleep)
COUNT=20
while [ "$COUNT" -gt 0 ]; do
    echo "Checking that the ACL token exists when reading it in the stale consistency mode ($COUNT attempts remaining)"
    if read_token_stale; then
        echo "Successfully read ACL token from the server"
        break
    fi
    sleep 0.1
    COUNT=$((COUNT - 1))
done
if [ "$COUNT" -eq 0 ]; then
   echo "Unable to read ACL token from a Consul server; please check that your server cluster is healthy"
   exit 1
fi

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
