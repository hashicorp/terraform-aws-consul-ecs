// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package wan

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

type wan struct {
	name string
}

func New(name string) scenarios.Scenario {
	return &wan{
		name: "mesh",
	}
}

func (w *wan) GetFolderName() string {
	return "mesh-gateways"
}

func (w *wan) GetTerraformVars() (map[string]interface{}, error) {
	vars := map[string]interface{}{
		"region": "us-east-1",
		"name":   w.name,
	}

	publicIP, err := common.GetPublicIP()
	if err != nil {
		return nil, err
	}
	vars["lb_ingress_ip"] = publicIP

	return vars, nil
}

func (w *wan) Validate(t *testing.T, outputVars map[string]interface{}) {
	logger.Log(t, "Fetching required output terraform variables")
	getOutputVariableValue := func(name string) string {
		val, ok := outputVars[name].(string)
		require.True(t, ok)
		return val
	}

	dc1ConsulServerURL := getOutputVariableValue("dc1_server_url")
	dc2ConsulServerURL := getOutputVariableValue("dc2_server_url")
	dc1ConsulServerToken := getOutputVariableValue("bootstrap_token")

	meshClientLBAddr := getOutputVariableValue("client_lb_address")
	meshClientLBAddr = strings.TrimSuffix(meshClientLBAddr, "/ui")

	logger.Log(t, "Setting up the Consul clients")
	consulClientOne, err := common.SetupConsulClient(dc1ConsulServerURL, dc1ConsulServerToken)
	require.NoError(t, err)

	consulClientTwo, err := common.SetupConsulClient(dc2ConsulServerURL, dc1ConsulServerToken)
	require.NoError(t, err)

	clientAppName := fmt.Sprintf("%s-dc1-example-client-app", w.name)
	serverAppName := fmt.Sprintf("%s-dc2-example-server-app", w.name)

	checkServiceExistence(t, consulClientOne, clientAppName)
	checkServiceExistence(t, consulClientTwo, serverAppName)

	meshGatewayDC1 := fmt.Sprintf("%s-dc1-mesh-gateway", w.name)
	meshGatewayDC2 := fmt.Sprintf("%s-dc2-mesh-gateway", w.name)

	checkServiceExistence(t, consulClientOne, meshGatewayDC1)
	checkServiceExistence(t, consulClientTwo, meshGatewayDC2)

	// Perform assertions by hitting the client app's LB
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		logger.Log(t, "calling client app's load balancer to see if the server app in the secondary datacenter is reachable")
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
