#!/bin/bash

waitfor() {
  echo -n "waiting for ${1}/${2}/${3} to be registered in Consul"
  local count=0
  while [[ $count -le 30 ]]; do
    echo -n "."
    echo $(curl -sS -X GET \
      -H "Authorization: Bearer ${CONSUL_HTTP_TOKEN}"\
      "${CONSUL_HTTP_ADDR}/v1/catalog/services?partition=${1}&ns=${2}") \
      | grep -q "${3}" && return
    sleep 10
    ((count++))
  done
  echo ""
  echo "timeout waiting for ${1}/${2}/${3}"
}

# get Terraform outputs and initialize required variables.
echo "loading Terraform outputs"
tfOutputs=$(cd terraform ; terraform output -json)
CONSUL_HTTP_ADDR=$(echo "$tfOutputs" | jq -rc '.hcp_public_endpoint.value')
CONSUL_HTTP_TOKEN=$(echo "$tfOutputs" | jq -rc '.token.value')

CLIENT_REGION=$(echo "$tfOutputs" | jq -rc '.client.value.region')
CLIENT_CLUSTER_ARN=$(echo "$tfOutputs" | jq -rc '.client.value.ecs_cluster_arn')
CLIENT_NAME=$(echo "$tfOutputs" | jq -rc '.client.value.name')
CLIENT_AP=$(echo "$tfOutputs" | jq -rc '.client.value.partition')
CLIENT_NS=$(echo "$tfOutputs" | jq -rc '.client.value.namespace')

SERVER_REGION=$(echo "$tfOutputs" | jq -rc '.server.value.region')
SERVER_CLUSTER_ARN=$(echo "$tfOutputs" | jq -rc '.server.value.ecs_cluster_arn')
SERVER_NAME=$(echo "$tfOutputs" | jq -rc '.server.value.name')
SERVER_AP=$(echo "$tfOutputs" | jq -rc '.server.value.partition')
SERVER_NS=$(echo "$tfOutputs" | jq -rc '.server.value.namespace')

# wait for services to be registered in Consul
waitfor ${CLIENT_AP} ${CLIENT_NS} ${CLIENT_NAME}
echo ""

waitfor ${SERVER_AP} ${SERVER_NS} ${SERVER_NAME}
echo ""

# retrieve the ECS task ID for the client
CLIENT_TASK_ID=$(aws ecs list-tasks --region ${CLIENT_REGION} --cluster ${CLIENT_CLUSTER_ARN} --family ${CLIENT_NAME} | jq -r '.taskArns[0]')

# make the upstream service call to the example server
echo -n "calling upstream ${SERVER_AP}/${SERVER_NS}/${SERVER_NAME} from client task"

# make the call to the upstream in a loop because it may take some time for the
# exported-service config and service intention to propagate.
count=0
success=false
while [[ $count -le 10 ]]; do
  echo -n "."
  response=$(aws ecs execute-command --region ${CLIENT_REGION} --cluster ${CLIENT_CLUSTER_ARN} --task ${CLIENT_TASK_ID} --container=basic --command '/bin/sh -c "curl localhost:1234"' --interactive 2> /dev/null)
  if echo "$response" | grep -q 'Hello World'; then
    echo $response
    success=true
    break
  fi
  sleep 20
  ((count++))
done

if [ ! "$success" ]; then
    echo "e2e setup for Consul on ECS using admin partitions failed!!"
    exit 1
fi

echo "e2e setup for Consul on ECS using admin partitions is successful!!"
