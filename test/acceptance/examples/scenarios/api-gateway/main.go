// Copyright IBM Corp. 2021, 2025
// SPDX-License-Identifier: MPL-2.0

package apigateway

import (
	"encoding/json"
	"fmt"
	"testing"

	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type TFOutputs struct {
	ConsulServerLBAddr string `json:"consul_server_lb_address"`
	ConsulServerToken  string `json:"consul_server_bootstrap_token"`
	APIGatewayLBURL    string `json:"api_gateway_lb_url"`
}

func RegisterScenario(r scenarios.ScenarioRegistry) {
	tfResourcesName := fmt.Sprintf("ecs-%s", common.GenerateRandomStr(6))

	r.Register(scenarios.ScenarioRegistration{
		Name:               "API_GATEWAY",
		FolderName:         "api-gateway",
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
	return func(t *testing.T, data []byte) {
		logger.Log(t, "Fetching required output terraform variables")

		var tfOutputs *TFOutputs
		require.NoError(t, json.Unmarshal(data, &tfOutputs))

		consulServerLBAddr := tfOutputs.ConsulServerLBAddr
		apiGatewayLBURL := tfOutputs.APIGatewayLBURL

		logger.Log(t, "Setting up the Consul client")
		consulClient, err := common.SetupConsulClient(t, consulServerLBAddr)
		require.NoError(t, err)

		clientAppName := fmt.Sprintf("%s-example-client-app", tfResName)
		serverAppName := fmt.Sprintf("%s-example-server-app", tfResName)

		consulClient.EnsureServiceReadiness(clientAppName, nil)
		consulClient.EnsureServiceReadiness(serverAppName, nil)
		consulClient.EnsureServiceReadiness(fmt.Sprintf("%s-api-gateway", tfResName), nil)

		// Perform assertions by hitting the gateway's LB
		logger.Log(t, "calling API gateway's load balancer to see if the server app is reachable")
		common.ValidateFakeServiceResponse(t, apiGatewayLBURL, serverAppName)

		// Test if the API gateway load balances requests

		// Append the path `/echo` to the LB's URL.
		apiGatewayLBURL = fmt.Sprintf("%s/echo", apiGatewayLBURL)

		type echoServiceResp struct {
			Service string `json:"service"`
		}

		// We hit the API gateway's LB URL along with the `/echo` path for a finite number
		// of times to check if the gateway performs weighted load balancing between
		// the two replicas of the echo service.
		svcMap := make(map[string]struct{})
		for i := 0; i <= 20; i++ {
			resp, err := common.HTTPGet(apiGatewayLBURL)
			require.NoError(t, err)

			var echoSvcResp *echoServiceResp
			require.NoError(t, json.Unmarshal(resp, &echoSvcResp))

			fmt.Println(echoSvcResp.Service)
			svcMap[echoSvcResp.Service] = struct{}{}
		}

		// Ensure that both the echo service's were hit
		require.Len(t, svcMap, 2)
	}
}
