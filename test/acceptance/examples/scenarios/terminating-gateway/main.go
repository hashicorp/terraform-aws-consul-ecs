// Copyright IBM Corp. 2021, 2025
// SPDX-License-Identifier: MPL-2.0

package terminatinggateway

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type TFOutputs struct {
	ConsulServerLBAddr string `json:"consul_server_lb_address"`
	ConsulServerToken  string `json:"consul_server_bootstrap_token"`
	MeshClientLBAddr   string `json:"mesh_client_lb_address"`
}

func RegisterScenario(r scenarios.ScenarioRegistry) {
	tfResourcesName := fmt.Sprintf("ecs-%s", common.GenerateRandomStr(6))

	r.Register(scenarios.ScenarioRegistration{
		Name:               "TERMINATING_GATEWAY",
		FolderName:         "terminating-gateway",
		TerraformInputVars: getTerraformVars(tfResourcesName),
		Validate:           validate(tfResourcesName),
	})
}

func getTerraformVars(tfResName string) scenarios.TerraformInputVarsHook {
	return func() (map[string]interface{}, error) {
		vars := map[string]interface{}{
			"region": "us-east-2",
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
	return func(t *testing.T, data []byte) {
		logger.Log(t, "Fetching required output terraform variables")

		var tfOutputs *TFOutputs
		require.NoError(t, json.Unmarshal(data, &tfOutputs))

		consulServerLBAddr := tfOutputs.ConsulServerLBAddr
		meshClientLBAddr := tfOutputs.MeshClientLBAddr
		meshClientLBAddr = strings.TrimSuffix(meshClientLBAddr, "/ui")

		logger.Log(t, "Setting up the Consul client")
		consulClient, err := common.SetupConsulClient(t, consulServerLBAddr)
		require.NoError(t, err)

		clientAppName := fmt.Sprintf("%s-example-client-app", tfResName)
		serverAppName := fmt.Sprintf("%s-external-server-app", tfResName)

		consulClient.EnsureServiceReadiness(clientAppName, nil)
		consulClient.EnsureServiceReadiness(serverAppName, nil)

		// Perform assertions by hitting the client app's LB
		logger.Log(t, "calling client app's load balancer to see if the server app is reachable")
		common.ValidateFakeServiceResponse(t, meshClientLBAddr, serverAppName)
	}
}
