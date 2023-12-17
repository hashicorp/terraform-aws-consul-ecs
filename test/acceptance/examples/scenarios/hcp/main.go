// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package hcp

import (
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type hcp struct{}

type service struct {
	awsRegion     string
	ecsClusterARN string
	name          string
	partition     string
	namespace     string
}

func New(name string) scenarios.Scenario {
	return &hcp{}
}

func (h *hcp) GetFolderName() string {
	return "admin-partitions/terraform"
}

func (h *hcp) GetTerraformVars() (map[string]interface{}, error) {
	vars := map[string]interface{}{
		"region": "us-west-2",
	}

	hcpProjectID := os.Getenv("HCP_PROJECT_ID")
	if hcpProjectID == "" {
		return nil, fmt.Errorf("expected HCP_PROJECT_ID to be non empty")
	}
	vars["hcp_project_id"] = hcpProjectID

	return vars, nil
}

func (h *hcp) Validate(t *testing.T, outputVars map[string]interface{}) {
	logger.Log(t, "Fetching required output terraform variables")
	getOutputVariableValue := func(name string) string {
		val, ok := outputVars[name].(string)
		require.True(t, ok)
		return val
	}
	consulServerLBAddr := getOutputVariableValue("hcp_public_endpoint")
	consulServerToken := getOutputVariableValue("token")

	logger.Log(t, outputVars)
	clientService := getServiceDetails(t, "client", outputVars)
	serverService := getServiceDetails(t, "server", outputVars)

	logger.Log(t, "Setting up the Consul client")
	consulClient, err := common.SetupConsulClient(consulServerLBAddr, consulServerToken)
	require.NoError(t, err)

	checkServiceExistence(t, consulClient, clientService)
	checkServiceExistence(t, consulClient, serverService)

	logger.Log(t, "Setting up ECS client")

	ecsClient, err := common.NewECSClient()
	require.NoError(t, err)

	// List tasks for the client service
	tasks, err := ecsClient.WithClusterARN(clientService.ecsClusterARN).ListTasksForService(clientService.name)
	require.NoError(t, err)
	require.Len(t, tasks, 1)
	// Perform assertions by hitting the client app's LB
	// retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
	// 	logger.Log(t, "calling client app's load balancer to see if the server app is reachable")
	// 	resp, err := common.GetFakeServiceResponse(meshClientLBAddr)
	// 	require.NoError(r, err)

	// 	require.Equal(r, 200, resp.Code)
	// 	require.Equal(r, "Hello World", resp.Body)
	// 	require.NotNil(r, resp.UpstreamCalls)

	// 	upstreamResp := resp.UpstreamCalls["http://localhost:1234"]
	// 	require.NotNil(r, upstreamResp)
	// 	require.Equal(r, serverAppName, upstreamResp.Name)
	// 	require.Equal(r, 200, upstreamResp.Code)
	// 	require.Equal(r, "Hello World", upstreamResp.Body)
	// })
}

func getServiceDetails(t *testing.T, name string, outputVars map[string]interface{}) *service {
	val, ok := outputVars[name].(map[string]string)
	require.True(t, ok)

	ensureAndReturnNonEmptyVal := func(v string) string {
		require.NotEmpty(t, v)
		return v
	}

	return &service{
		name:          ensureAndReturnNonEmptyVal(val["name"]),
		awsRegion:     ensureAndReturnNonEmptyVal(val["region"]),
		ecsClusterARN: ensureAndReturnNonEmptyVal(val["ecs_cluster_arn"]),
		partition:     ensureAndReturnNonEmptyVal(val["partition"]),
		namespace:     ensureAndReturnNonEmptyVal(val["namespace"]),
	}
}

func checkServiceExistence(t *testing.T, consulClient *api.Client, service *service) {
	logger.Log(t, fmt.Sprintf("checking if service %s is registered in Consul in the %s namespace under %s partition",
		service.name,
		service.namespace,
		service.partition,
	))

	opts := &api.QueryOptions{
		Namespace: service.namespace,
		Partition: service.partition,
	}

	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		exists, err := common.ServiceExists(consulClient, service.name, opts)
		require.NoError(r, err)
		require.True(r, exists)
	})
}
