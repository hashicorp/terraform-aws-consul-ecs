// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package fargate

import (
	"fmt"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

func RegisterScenario(r scenarios.ScenarioRegistry) {
	tfResourcesName := strings.ToLower(fmt.Sprintf("ecs-%s", random.UniqueId()))

	r.Register(scenarios.ScenarioRegistration{
		Name:               "FARGATE",
		FolderName:         "dev-server-fargate",
		TerraformInputVars: getTerraformVars(tfResourcesName),
		Validate:           validate(tfResourcesName),
	})
}

func getTerraformVars(tfResName string) scenarios.TerraformInputVarsHook {
	return func() (map[string]interface{}, error) {
		vars := map[string]interface{}{
			"region": "us-east-1",
			"name":   tfResName,
		}

		publicIP, err := common.GetPublicIP()
		if err != nil {
			return nil, err
		}
		vars["lb_ingress_ip"] = publicIP

		return vars, nil
	}
}

func validate(tfResName string) scenarios.ValidateHook {
	return func(t *testing.T, outputVars map[string]interface{}) {
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

		clientAppName := fmt.Sprintf("%s-example-client-app", tfResName)
		serverAppName := fmt.Sprintf("%s-example-server-app", tfResName)

		consulClient.EnsureServiceReadiness(clientAppName, nil)
		consulClient.EnsureServiceReadiness(serverAppName, nil)

		// Perform assertions by hitting the client app's LB
		logger.Log(t, "calling client app's load balancer to see if the server app is reachable")
		common.ValidateFakeServiceResponse(t, meshClientLBAddr, serverAppName)
	}
}
