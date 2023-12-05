#!/bin/bash

# Script that validates if the setup works E2E on ECS.
set -e

waitfor() {
  echo -n "waiting for ${1} to be registered in Consul"
  local count=0
  while [[ $count -le 30 ]]; do
    echo -n "."
    echo $(curl -sS -X GET \
      "${CONSUL_HTTP_ADDR}/v1/catalog/services") \
      | grep -q "${1}" && return
    sleep 10
    ((count++))
  done
  echo ""
  echo "timeout waiting for ${1}"
  exit 1
}

# get Terraform outputs and initialize required variables.
echo "loading Terraform outputs"
tfOutputs=$(terraform output -json)
CONSUL_HTTP_ADDR=$(echo "$tfOutputs" | jq -rc '.consul_server_lb_address.value')
MESH_CLIENT_APP_LB_ADDR=$(echo "$tfOutputs" | jq -rc '.mesh_client_lb_address.value')
MESH_CLIENT_APP_LB_ADDR="${MESH_CLIENT_APP_LB_ADDR%/ui}"

CLIENT_APP_NAME=$(echo "$tfOutputs" | jq -rc '.client_app_consul_service_name.value')
SERVER_APP_NAME=$(echo "$tfOutputs" | jq -rc '.server_app_consul_service_name.value')

# wait for services to be registered in Consul
waitfor ${CLIENT_APP_NAME}
echo ""

waitfor ${SERVER_APP_NAME}
echo ""

# hit the client app's LB to check if the server app is reachable
echo -n "calling client app's load balancer"

# make the call to the upstream in a loop because it may take some time for the
# exported-service config and service intention to propagate.
count=0
success=false
while [[ $count -le 20 ]]; do
  echo -n "."
  response=$(curl -s ${MESH_CLIENT_APP_LB_ADDR} 2> /dev/null)
  if echo "$response" | grep -q 'Hello World'; then
    echo "$response"
    success=true
    break
  fi
  sleep 20
  ((count++))
done
echo ""

if [ ! "$success" ]; then
    echo "e2e setup for Consul on ECS Fargate failed!!"
    exit 1
fi

echo "e2e setup for Consul on ECS Fargate is successful!!"