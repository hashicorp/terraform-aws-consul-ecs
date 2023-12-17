// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package clusterpeering

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type clusterPeering struct {
	name string
}

func New(name string) scenarios.Scenario {
	// We go ahead with a simple name due to AWS restrictions
	// on character length of resource names for certain resources.
	return &clusterPeering{
		name: "ecs",
	}
}

func (c *clusterPeering) GetFolderName() string {
	return "cluster-peering"
}

func (c *clusterPeering) GetTerraformVars() (map[string]interface{}, error) {
	vars := map[string]interface{}{
		"region": "us-east-2",
		"name":   c.name,
	}

	publicIP, err := common.GetPublicIP()
	if err != nil {
		return nil, err
	}
	vars["lb_ingress_ip"] = publicIP

	return vars, nil
}

func (c *clusterPeering) Validate(t *testing.T, outputVars map[string]interface{}) {
	logger.Log(t, "Fetching required output terraform variables")
	getOutputVariableValue := func(name string) string {
		val, ok := outputVars[name].(string)
		require.True(t, ok)
		return val
	}

	dc1ConsulServerURL := getOutputVariableValue("dc1_server_url")
	dc2ConsulServerURL := getOutputVariableValue("dc2_server_url")
	dc1ConsulServerToken := getOutputVariableValue("dc1_server_bootstrap_token")
	dc2ConsulServerToken := getOutputVariableValue("dc2_server_bootstrap_token")

	meshClientLBAddr := getOutputVariableValue("client_lb_address")
	meshClientLBAddr = strings.TrimSuffix(meshClientLBAddr, "/ui")

	logger.Log(t, "Setting up the Consul clients")
	consulClientOne, err := common.SetupConsulClient(dc1ConsulServerURL, dc1ConsulServerToken)
	require.NoError(t, err)

	consulClientTwo, err := common.SetupConsulClient(dc2ConsulServerURL, dc2ConsulServerToken)
	require.NoError(t, err)

	clientAppName := fmt.Sprintf("%s-dc1-example-client-app", c.name)
	serverAppName := fmt.Sprintf("%s-dc2-example-server-app", c.name)

	checkServiceExistence(t, consulClientOne, clientAppName)
	checkServiceExistence(t, consulClientTwo, serverAppName)

	meshGatewayDC1 := fmt.Sprintf("%s-dc1-mesh-gateway", c.name)
	meshGatewayDC2 := fmt.Sprintf("%s-dc2-mesh-gateway", c.name)

	checkServiceExistence(t, consulClientOne, meshGatewayDC1)
	checkServiceExistence(t, consulClientTwo, meshGatewayDC2)

	// Perform assertions by hitting the client app's LB
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		logger.Log(t, "calling client app's load balancer to see if the server app in the peer cluster is reachable")
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
