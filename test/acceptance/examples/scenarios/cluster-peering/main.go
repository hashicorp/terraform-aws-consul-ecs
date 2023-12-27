// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package clusterpeering

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
	DC1ConsulServerAddr  string `json:"dc1_server_url"`
	DC1ConsulServerToken string `json:"dc1_server_bootstrap_token"`
	DC2ConsulServerAddr  string `json:"dc2_server_url"`
	DC2ConsulServerToken string `json:"dc2_server_bootstrap_token"`
	MeshClientLBAddr     string `json:"client_lb_address"`
}

func RegisterScenario(r scenarios.ScenarioRegistry) {
	tfResourcesName := common.GenerateRandomStr(4)

	r.Register(scenarios.ScenarioRegistration{
		Name:               "CLUSTER_PEERING",
		FolderName:         "cluster-peering",
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
		tfOutputs.MeshClientLBAddr = strings.TrimSuffix(tfOutputs.MeshClientLBAddr, "/ui")

		logger.Log(t, "Setting up the Consul clients")
		consulClientOne, err := common.SetupConsulClient(t, tfOutputs.DC1ConsulServerAddr, common.WithToken(tfOutputs.DC1ConsulServerToken))
		require.NoError(t, err)

		consulClientTwo, err := common.SetupConsulClient(t, tfOutputs.DC2ConsulServerAddr, common.WithToken(tfOutputs.DC2ConsulServerToken))
		require.NoError(t, err)

		clientAppName := fmt.Sprintf("%s-dc1-example-client-app", tfResName)
		serverAppName := fmt.Sprintf("%s-dc2-example-server-app", tfResName)

		consulClientOne.EnsureServiceReadiness(clientAppName, nil)
		consulClientTwo.EnsureServiceReadiness(serverAppName, nil)
		consulClientOne.EnsureServiceReadiness(fmt.Sprintf("%s-dc1-mesh-gateway", tfResName), nil)
		consulClientTwo.EnsureServiceReadiness(fmt.Sprintf("%s-dc2-mesh-gateway", tfResName), nil)

		// Perform assertions by hitting the client app's LB
		logger.Log(t, "calling client app's load balancer to see if the server app in the peer cluster is reachable")
		common.ValidateFakeServiceResponse(t, tfOutputs.MeshClientLBAddr, serverAppName)
	}
}
