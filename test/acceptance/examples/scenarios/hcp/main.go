// Copyright IBM Corp. 2021, 2025
// SPDX-License-Identifier: MPL-2.0

package hcp

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/serf/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type TFOutputs struct {
	HCPConsulServerAddr  string `json:"hcp_public_endpoint"`
	HCPConsulServerToken string `json:"token"`
	ClientApp            *App   `json:"client"`
	ServerApp            *App   `json:"server"`
}

type App struct {
	Name          string `json:"name"`
	ECSClusterARN string `json:"ecs_cluster_arn"`
	Region        string `json:"region"`
	Partition     string `json:"partition"`
	Namespace     string `json:"namespace"`
}

func RegisterScenario(r scenarios.ScenarioRegistry) {
	r.Register(scenarios.ScenarioRegistration{
		Name:               "HCP",
		FolderName:         "admin-partitions/terraform",
		TerraformInputVars: getTerraformVars(),
		Validate:           validate(),
	})
}

func getTerraformVars() scenarios.TerraformInputVarsHook {
	return func() (map[string]interface{}, error) {
		vars := map[string]interface{}{
			"region": "us-west-2",
		}

		hcpProjectID := os.Getenv("HCP_PROJECT_ID")
		if hcpProjectID == "" {
			return nil, fmt.Errorf("expected HCP_PROJECT_ID to be non empty")
		}
		vars["hcp_project_id"] = hcpProjectID

		return vars, nil
	}
}

func validate() scenarios.ValidateHook {
	return func(t *testing.T, data []byte) {
		logger.Log(t, "Fetching required output terraform variables")

		var tfOutputs *TFOutputs
		require.NoError(t, json.Unmarshal(data, &tfOutputs))

		logger.Log(t, "Setting up the Consul client")
		consulClient, err := common.SetupConsulClient(t, tfOutputs.HCPConsulServerAddr, common.WithToken(tfOutputs.HCPConsulServerToken))
		require.NoError(t, err)

		ensureServiceReadiness(consulClient, tfOutputs.ClientApp)
		ensureServiceReadiness(consulClient, tfOutputs.ServerApp)

		logger.Log(t, "Setting up ECS client")

		ecsClient, err := common.NewECSClient()
		require.NoError(t, err)

		// List tasks for the client service
		tasks, err := ecsClient.WithClusterARN(tfOutputs.ClientApp.ECSClusterARN).ListTasksForService(tfOutputs.ClientApp.Name)
		require.NoError(t, err)
		require.Len(t, tasks, 1)

		// Validate connection between apps by running a remote command inside the container.
		retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
			res, err := ecsClient.
				WithClusterARN(tfOutputs.ClientApp.ECSClusterARN).
				ExecuteCommandInteractive(t, tasks[0], "basic", `/bin/sh -c "curl localhost:1234"`)
			r.Check(err)
			if !strings.Contains(res, `"code": 200`) {
				r.Errorf("response was unexpected: %q", res)
			}
		})
	}
}

func ensureServiceReadiness(consulClient *common.ConsulClientWrapper, service *App) {
	opts := &api.QueryOptions{
		Namespace: service.Namespace,
		Partition: service.Partition,
	}
	consulClient.EnsureServiceReadiness(service.Name, opts)
}
