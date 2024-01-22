// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package localityawarerouting

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/hashicorp/serf/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type TFOutputs struct {
	ConsulServerAddr  string `json:"consul_server_url"`
	ConsulServerToken string `json:"consul_server_bootstrap_token"`
	MeshClientLBAddr  string `json:"client_lb_address"`
	ECSClusterARN     string `json:"ecs_cluster_arn"`
}

func RegisterScenario(r scenarios.ScenarioRegistry) {
	tfResName := common.GenerateRandomStr(4)
	r.Register(scenarios.ScenarioRegistration{
		Name:               "LOCALITY_AWARE_ROUTING",
		FolderName:         "locality-aware-routing",
		TerraformInputVars: getTerraformVars(tfResName),
		Validate:           validate(tfResName),
	})
}

func getTerraformVars(tfResName string) scenarios.TerraformInputVarsHook {
	return func() (map[string]interface{}, error) {
		vars := map[string]interface{}{
			"region": "us-west-2",
			"name":   tfResName,
		}

		publicIP, err := common.GetPublicIP()
		if err != nil {
			return nil, err
		}
		vars["lb_ingress_ip"] = publicIP

		enterpriseLicense := os.Getenv("CONSUL_LICENSE")
		if enterpriseLicense == "" {
			return nil, fmt.Errorf("expected CONSUL_LICENSE to be non empty")
		}
		vars["consul_license"] = enterpriseLicense

		return vars, nil
	}
}

func validate(tfResName string) scenarios.ValidateHook {
	return func(t *testing.T, data []byte) {
		logger.Log(t, "Fetching required output terraform variables")

		var tfOutputs *TFOutputs
		require.NoError(t, json.Unmarshal(data, &tfOutputs))
		tfOutputs.MeshClientLBAddr = strings.TrimSuffix(tfOutputs.MeshClientLBAddr, "/ui")

		logger.Log(t, "Setting up the Consul client")
		consulClient, err := common.SetupConsulClient(t, tfOutputs.ConsulServerAddr, common.WithToken(tfOutputs.ConsulServerToken))
		require.NoError(t, err)

		clientAppName := "example-client-app"
		serverAppName := "example-server-app"

		consulClient.EnsureServiceReadiness(clientAppName, nil)
		consulClient.EnsureServiceReadiness(serverAppName, nil)

		consulClient.EnsureServiceInstances(serverAppName, 2, nil)

		ecsClient, err := common.NewECSClient(common.WithClusterARN(tfOutputs.ECSClusterARN))
		require.NoError(t, err)

		logger.Log(t, "Listing and describing tasks for each ECS service")
		clientTasks := assertAndListTasks(t, ecsClient, clientAppName, 1)
		serverTasks := assertAndListTasks(t, ecsClient, serverAppName, 2)

		// Describe the client task
		tasks := assertAndDescribeTasks(t, ecsClient, clientTasks, 1)
		clientTask := tasks[0]

		// Describe the server tasks
		tasks = assertAndDescribeTasks(t, ecsClient, serverTasks, 2)
		serverTaskIPMap := getTaskIPToTaskMap(t, tasks)

		performAssertions := func(expectSameAZ bool) {
			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
				resp, err := common.GetFakeServiceResponse(tfOutputs.MeshClientLBAddr)
				require.NoError(r, err)

				require.Equal(r, 200, resp.Code)
				require.Equal(r, "Hello World", resp.Body)
				require.NotNil(r, resp.UpstreamCalls)

				upstreamResp := resp.UpstreamCalls["http://localhost:1234"]
				require.NotNil(r, upstreamResp)
				require.Equal(r, serverAppName, upstreamResp.Name)
				require.Equal(r, 200, upstreamResp.Code)
				require.Equal(r, "Hello World", upstreamResp.Body)

				var upstreamServerTask types.Task
				var ok bool
				for _, ip := range upstreamResp.IpAddresses {
					upstreamServerTask, ok = serverTaskIPMap[ip]
					if ok {
						break
					}
				}

				// Check if the client app's AZ matches with that of the server task
				if expectSameAZ {
					require.Equal(r, clientTask.AvailabilityZone, upstreamServerTask.AvailabilityZone)
				} else {
					require.NotEqual(r, clientTask.AvailabilityZone, upstreamServerTask.AvailabilityZone)
				}
			})
		}

		logger.Log(t, "Calling the client app's load balancer to verify if the client app hits the server app in the same availability zone")
		performAssertions(true)

		// Stop the server app present in the same AZ as that of the client
		var serverTaskToStop types.Task
		for _, v := range tasks {
			if *v.AvailabilityZone == *clientTask.AvailabilityZone {
				serverTaskToStop = v
				break
			}
		}

		logger.Log(t, "Stopping the server app's task present in the same AZ as that of the client.")
		require.NoError(t, ecsClient.StopTask(*serverTaskToStop.TaskArn, "stopping as part of a test"))

		logger.Log(t, "Calling the client app's load balancer to verify if the client app falls back to hit the server app in the other availability zone")
		performAssertions(false)

		retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
			logger.Log(t, "Waiting for ECS to spin up the previously stopped server app's task")
			serverTasks, err = ecsClient.ListTasksForService(serverAppName)
			require.NoError(r, err)
			require.Len(r, serverTasks, 2)
		})

		tasks = assertAndDescribeTasks(t, ecsClient, serverTasks, 2)
		serverTaskIPMap = getTaskIPToTaskMap(t, tasks)

		logger.Log(t, "Calling the client app's load balancer to verify if the client app hits the server app in the same availability zone")
		performAssertions(true)
	}
}

func assertAndListTasks(t *testing.T, ecsClient *common.ECSClientWrapper, service string, expectedCount int) []string {
	tasks, err := ecsClient.ListTasksForService(service)
	require.NoError(t, err)
	require.Len(t, tasks, expectedCount)

	return tasks
}

func assertAndDescribeTasks(t *testing.T, ecsClient *common.ECSClientWrapper, taskIDs []string, expectedCount int) []types.Task {
	tasks, err := ecsClient.DescribeTasks(taskIDs)
	require.NoError(t, err)
	require.NotNil(t, tasks)
	require.Len(t, tasks.Tasks, expectedCount)

	return tasks.Tasks
}

func getTaskIPToTaskMap(t *testing.T, tasks []types.Task) map[string]types.Task {
	serverTaskIPMap := make(map[string]types.Task)
	for _, task := range tasks {
		serverTaskIPMap[getTaskPrivateIP(t, task)] = task
	}

	return serverTaskIPMap
}

func getTaskPrivateIP(t *testing.T, task types.Task) string {
	require.NotNil(t, task)
	require.NotEmpty(t, task.Containers)
	require.NotEmpty(t, task.Containers[0].NetworkInterfaces)

	ip := task.Containers[0].NetworkInterfaces[0].PrivateIpv4Address
	require.NotNil(t, ip)
	return *ip
}
