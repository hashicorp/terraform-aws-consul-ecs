// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package clusterpeering

import (
	"fmt"
	"strings"
	"testing"

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
	consulClientOne, err := common.SetupConsulClient(t, dc1ConsulServerURL, common.WithToken(dc1ConsulServerToken))
	require.NoError(t, err)

	consulClientTwo, err := common.SetupConsulClient(t, dc2ConsulServerURL, common.WithToken(dc2ConsulServerToken))
	require.NoError(t, err)

	clientAppName := fmt.Sprintf("%s-dc1-example-client-app", c.name)
	serverAppName := fmt.Sprintf("%s-dc2-example-server-app", c.name)

	consulClientOne.EnsureServiceReadiness(clientAppName, nil)
	consulClientTwo.EnsureServiceReadiness(serverAppName, nil)
	consulClientOne.EnsureServiceReadiness(fmt.Sprintf("%s-dc1-mesh-gateway", c.name), nil)
	consulClientTwo.EnsureServiceReadiness(fmt.Sprintf("%s-dc2-mesh-gateway", c.name), nil)

	// Perform assertions by hitting the client app's LB
	logger.Log(t, "calling client app's load balancer to see if the server app in the peer cluster is reachable")
	common.ValidateFakeServiceResponse(t, meshClientLBAddr, serverAppName)
}
