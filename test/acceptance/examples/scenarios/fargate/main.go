// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package fargate

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/serf/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type fargate struct {
	name string
}

func New(name string) scenarios.Scenario {
	return &fargate{
		name: name,
	}
}

func (f *fargate) GetFolderName() string {
	return "dev-server-fargate"
}

func (f *fargate) GetTerraformVars() (map[string]interface{}, error) {
	vars := map[string]interface{}{
		"region": "us-east-1",
		"name":   f.name,
	}

	publicIP, err := common.GetPublicIP()
	if err != nil {
		return nil, err
	}
	vars["lb_ingress_ip"] = publicIP

	return vars, nil
}

func (f *fargate) Validate(t *testing.T, outputVars map[string]interface{}) {
	logger.Log(t, "Fetching required output terraform variables")
	consulServerLBAddr, ok := outputVars["consul_server_lb_address"].(string)
	require.True(t, ok)

	meshClientLBAddr, ok := outputVars["mesh_client_lb_address"].(string)
	require.True(t, ok)

	meshClientLBAddr = strings.TrimSuffix(meshClientLBAddr, "/ui")

	logger.Log(t, "Setting up the Consul client")
	consulClient, err := common.SetupConsulClient(consulServerLBAddr, "")
	require.NoError(t, err)

	clientAppName := fmt.Sprintf("%s-example-client-app", f.name)
	serverAppName := fmt.Sprintf("%s-example-client-app", f.name)

	checkServiceExistence(t, consulClient, clientAppName)
	checkServiceExistence(t, consulClient, serverAppName)

	// Perform assertions by hitting the client app's LB
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		logger.Log(t, "calling client app's load balancer to see if the server app is reachable")
		resp, err := common.GetFakeServiceResponse(meshClientLBAddr)
		require.NoError(r, err)

		require.Equal(r, 200, resp.Code)
		require.Equal(r, "Hello World", resp.Body)
		require.NotNil(r, resp.UpstreamCalls)

		upstreamResp := resp.UpstreamCalls["http://localhost:1234"]
		require.NotNil(r, upstreamResp)
		require.Equal(r, serverAppName, upstreamResp.Name)
		require.Equal(r, 200, upstreamResp.Code)
		require.Equal(r, "Hello World", upstreamResp.Body)
	})
}

func checkServiceExistence(t *testing.T, consulClient *api.Client, name string) {
	logger.Log(t, fmt.Sprintf("checking if service %s is registered in Consul", name))
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		exists, err := common.ServiceExists(consulClient, name, nil)
		require.NoError(r, err)
		require.True(r, exists)
	})
}
