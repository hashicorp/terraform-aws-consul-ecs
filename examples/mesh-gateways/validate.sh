#!/bin/bash

# Script that validates if the setup works E2E on ECS.

waitfor() {
  echo -n "waiting for ${2} to be registered in Consul"
  local count=0
  while [[ $count -le 30 ]]; do
    echo -n "."
    response=$(curl -sS -X GET "${1}/v1/catalog/services")
    if [ $? -ne 0 ]; then
        echo "Error: curl command failed"
        ((count++))
        continue
    fi
    echo $response | grep -q "${2}" && return
    sleep 10
    ((count++))
  done
  echo ""
  echo "timeout waiting for ${2}"
  exit 1
}

# get Terraform outputs and initialize required variables.
echo "loading Terraform outputs"
tfOutputs=$(terraform output -json)
DC1_CONSUL_SERVER_ADDR=$(echo "$tfOutputs" | jq -rc '.dc1_server_url.value')
DC2_CONSUL_SERVER_ADDR=$(echo "$tfOutputs" | jq -rc '.dc2_server_url.value')

MESH_CLIENT_APP_LB_ADDR=$(echo "$tfOutputs" | jq -rc '.client_lb_address.value')
MESH_CLIENT_APP_LB_ADDR="${MESH_CLIENT_APP_LB_ADDR%/ui}"

CLIENT_APP_NAME=$(echo "$tfOutputs" | jq -rc '.client_app_consul_service_name.value')
SERVER_APP_NAME=$(echo "$tfOutputs" | jq -rc '.server_app_consul_service_name.value')

DC1_MESH_GW_NAME=$(echo "$tfOutputs" | jq -rc '.dc1_mesh_gateway_name.value')
DC2_MESH_GW_NAME=$(echo "$tfOutputs" | jq -rc '.dc2_mesh_gateway_name.value')

# wait for services to be registered in Consul
waitfor ${DC1_CONSUL_SERVER_ADDR} ${CLIENT_APP_NAME}
echo ""

waitfor ${DC2_CONSUL_SERVER_ADDR} ${SERVER_APP_NAME}
echo ""

waitfor ${DC1_CONSUL_SERVER_ADDR} ${DC1_MESH_GW_NAME}
echo ""

waitfor ${DC2_CONSUL_SERVER_ADDR} ${DC2_MESH_GW_NAME}
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
    echo "e2e setup for Mesh gateways on ECS failed!!"
    exit 1
fi

echo "e2e setup for Mesh gateways on ECS is successful!!"