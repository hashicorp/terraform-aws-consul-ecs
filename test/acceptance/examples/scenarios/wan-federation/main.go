// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package wan

import (
	"fmt"
	"strings"
	"testing"

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
	consulClientOne, err := common.SetupConsulClient(t, dc1ConsulServerURL, common.WithToken(dc1ConsulServerToken))
	require.NoError(t, err)

	consulClientTwo, err := common.SetupConsulClient(t, dc2ConsulServerURL, common.WithToken(dc1ConsulServerToken))
	require.NoError(t, err)

	clientAppName := fmt.Sprintf("%s-dc1-example-client-app", w.name)
	serverAppName := fmt.Sprintf("%s-dc2-example-server-app", w.name)

	consulClientOne.EnsureServiceReadiness(clientAppName, nil)
	consulClientTwo.EnsureServiceReadiness(serverAppName, nil)
	consulClientOne.EnsureServiceReadiness(fmt.Sprintf("%s-dc1-mesh-gateway", w.name), nil)
	consulClientTwo.EnsureServiceReadiness(fmt.Sprintf("%s-dc2-mesh-gateway", w.name), nil)

	// Perform assertions by hitting the client app's LB
	logger.Log(t, "calling client app's load balancer to see if the server app in the secondary DC is reachable")
	common.ValidateFakeServiceResponse(t, meshClientLBAddr, serverAppName)
}
