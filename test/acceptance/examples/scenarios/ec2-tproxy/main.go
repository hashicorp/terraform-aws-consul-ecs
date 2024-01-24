// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package ec2tproxy

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/hashicorp/serf/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type TFOutputs struct {
	ConsulServerLBAddr string `json:"consul_server_lb_address"`
	ConsulToken        string `json:"consul_server_bootstrap_token"`
	MeshClientLBAddr   string `json:"mesh_client_lb_address"`
}

func RegisterScenario(r scenarios.ScenarioRegistry) {
	tfResourcesName := fmt.Sprintf("ecs-%s", common.GenerateRandomStr(6))

	r.Register(scenarios.ScenarioRegistration{
		Name:               "EC2_TPROXY",
		FolderName:         "dev-server-ec2-transparent-proxy",
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
		consulToken := tfOutputs.ConsulToken
		meshClientLBAddr := tfOutputs.MeshClientLBAddr
		meshClientLBAddr = strings.TrimSuffix(meshClientLBAddr, "/ui")

		logger.Log(t, "Setting up the Consul client")
		consulClient, err := common.SetupConsulClient(t, consulServerLBAddr, common.WithToken(consulToken))
		require.NoError(t, err)

		clientAppName := fmt.Sprintf("%s-example-client-app", tfResName)
		serverAppName := fmt.Sprintf("%s-example-server-app", tfResName)

		consulClient.EnsureServiceReadiness(clientAppName, nil)
		consulClient.EnsureServiceReadiness(serverAppName, nil)

		// Perform assertions by hitting the client app's LB
		logger.Log(t, "calling client app's load balancer to see if the server app is reachable")

		var upstreamResp common.UpstreamCallResponse
		retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
			resp, err := common.GetFakeServiceResponse(meshClientLBAddr)
			require.NoError(r, err)

			require.Equal(r, 200, resp.Code)
			require.Equal(r, "Hello World", resp.Body)
			require.NotNil(r, resp.UpstreamCalls)

			upstreamResp = resp.UpstreamCalls[fmt.Sprintf("http://%s.virtual.consul", serverAppName)]
			require.NotNil(r, upstreamResp)
			require.Equal(r, serverAppName, upstreamResp.Name)
			require.Equal(r, 200, upstreamResp.Code)
			require.Equal(r, "Hello World", upstreamResp.Body)
		})
	}
}
