// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package hcp

import (
	"fmt"
	"os"
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

type service struct {
	awsRegion     string
	ecsClusterARN string
	name          string
	partition     string
	namespace     string
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
	return func(t *testing.T, tfOutput map[string]interface{}) {
		logger.Log(t, "Fetching required output terraform variables")
		getOutputVariableValue := func(name string) string {
			val, ok := tfOutput[name].(string)
			require.True(t, ok)
			return val
		}
		consulServerLBAddr := getOutputVariableValue("hcp_public_endpoint")
		consulServerToken := getOutputVariableValue("token")

		clientService := getServiceDetails(t, "client", tfOutput)
		serverService := getServiceDetails(t, "server", tfOutput)

		logger.Log(t, "Setting up the Consul client")
		consulClient, err := common.SetupConsulClient(t, consulServerLBAddr, common.WithToken(consulServerToken))
		require.NoError(t, err)

		ensureServiceReadiness(consulClient, clientService)
		ensureServiceReadiness(consulClient, serverService)

		logger.Log(t, "Setting up ECS client")

		ecsClient, err := common.NewECSClient()
		require.NoError(t, err)

		// List tasks for the client service
		tasks, err := ecsClient.WithClusterARN(clientService.ecsClusterARN).ListTasksForService(clientService.name)
		require.NoError(t, err)
		require.Len(t, tasks, 1)

		// Validate connection between apps by running a remote command inside the container.
		retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
			res, err := ecsClient.
				WithClusterARN(clientService.ecsClusterARN).
				ExecuteCommandInteractive(t, tasks[0], "basic", `/bin/sh -c "curl localhost:1234"`)
			r.Check(err)
			if !strings.Contains(res, `"code": 200`) {
				r.Errorf("response was unexpected: %q", res)
			}
		})
	}
}

func getServiceDetails(t *testing.T, name string, outputVars map[string]interface{}) *service {
	val, ok := outputVars[name].(map[string]interface{})
	require.True(t, ok)

	ensureAndReturnNonEmptyVal := func(v interface{}) string {
		require.NotEmpty(t, v)
		return v.(string)
	}

	return &service{
		name:          ensureAndReturnNonEmptyVal(val["name"]),
		awsRegion:     ensureAndReturnNonEmptyVal(val["region"]),
		ecsClusterARN: ensureAndReturnNonEmptyVal(val["ecs_cluster_arn"]),
		partition:     ensureAndReturnNonEmptyVal(val["partition"]),
		namespace:     ensureAndReturnNonEmptyVal(val["namespace"]),
	}
}

func ensureServiceReadiness(consulClient *common.ConsulClientWrapper, service *service) {
	opts := &api.QueryOptions{
		Namespace: service.namespace,
		Partition: service.partition,
	}
	consulClient.EnsureServiceReadiness(service.name, opts)
}
