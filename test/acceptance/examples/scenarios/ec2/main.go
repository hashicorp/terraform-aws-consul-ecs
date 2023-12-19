// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package ec2

import (
	"fmt"
	"strings"
	"testing"

	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type ec2 struct {
	name string
}

func New(name string) scenarios.Scenario {
	return &ec2{
		name: name,
	}
}

func (e *ec2) GetFolderName() string {
	return "dev-server-ec2"
}

func (e *ec2) GetTerraformVars() (map[string]interface{}, error) {
	vars := map[string]interface{}{
		"region": "us-east-2",
		"name":   e.name,
	}

	publicIP, err := common.GetPublicIP()
	if err != nil {
		return nil, err
	}
	vars["lb_ingress_ip"] = publicIP

	return vars, nil
}

func (e *ec2) Validate(t *testing.T, outputVars map[string]interface{}) {
	logger.Log(t, "Fetching required output terraform variables")
	getOutputVariableValue := func(name string) string {
		val, ok := outputVars[name].(string)
		require.True(t, ok)
		return val
	}

	consulServerLBAddr := getOutputVariableValue("consul_server_lb_address")
	meshClientLBAddr := getOutputVariableValue("mesh_client_lb_address")
	meshClientLBAddr = strings.TrimSuffix(meshClientLBAddr, "/ui")

	logger.Log(t, "Setting up the Consul client")
	consulClient, err := common.SetupConsulClient(t, consulServerLBAddr)
	require.NoError(t, err)

	clientAppName := fmt.Sprintf("%s-example-client-app", e.name)
	serverAppName := fmt.Sprintf("%s-example-server-app", e.name)

	consulClient.EnsureServiceReadiness(clientAppName, nil)
	consulClient.EnsureServiceReadiness(serverAppName, nil)

	// Perform assertions by hitting the client app's LB
	logger.Log(t, "calling client app's load balancer to see if the server app is reachable")
	common.ValidateFakeServiceResponse(t, meshClientLBAddr, serverAppName)
}
