// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package sameness

import (
	"encoding/json"
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

const (
	awsRegion = "us-west-1"
)

type TFOutputs struct {
	DC1ConsulServerAddr  string            `json:"dc1_server_url"`
	DC1ConsulServerToken string            `json:"dc1_server_bootstrap_token"`
	DC2ConsulServerAddr  string            `json:"dc2_server_url"`
	DC2ConsulServerToken string            `json:"dc2_server_bootstrap_token"`
	DC1DefaultPartition  *PartitionDetails `json:"dc1_default_partition_apps"`
	DC1Part1Partition    *PartitionDetails `json:"dc1_part1_partition_apps"`
	DC2DefaultPartition  *PartitionDetails `json:"dc2_default_partition_apps"`
}

type PartitionDetails struct {
	Partition     string `json:"partition"`
	Namespace     string `json:"namespace"`
	ECSClusterARN string `json:"ecs_cluster_arn"`
	Region        string `json:"region"`
	ClientApp     *App   `json:"client"`
	ServerApp     *App   `json:"server"`
}

func (p *PartitionDetails) getClientAppName() string       { return p.ClientApp.Name }
func (p *PartitionDetails) getServerAppName() string       { return p.ServerApp.Name }
func (p *PartitionDetails) getClientAppLBAddr() string     { return p.ClientApp.LBAddr }
func (p *PartitionDetails) getClientAppConsulName() string { return p.ClientApp.ConsulName }
func (p *PartitionDetails) getServerAppConsulName() string { return p.ServerApp.ConsulName }

type App struct {
	Name       string `json:"name"`
	ConsulName string `json:"consul_service_name"`
	LBAddr     string `json:"lb_address,omitempty"`
}

func RegisterScenario(r scenarios.ScenarioRegistry) {
	tfResName := "pjye" //common.GenerateRandomStr(4)

	r.Register(scenarios.ScenarioRegistration{
		Name:               "SERVICE_SAMENESS",
		FolderName:         "service-sameness",
		TerraformInputVars: getTerraformVars(tfResName),
		Validate:           validate(tfResName),
	})
}

func getTerraformVars(tfResName string) scenarios.TerraformInputVarsHook {
	return func() (map[string]interface{}, error) {
		vars := map[string]interface{}{
			"region": awsRegion,
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

		removeUISuffix := func(addr string) string {
			return strings.TrimSuffix(addr, "/ui")
		}
		tfOutputs.DC1DefaultPartition.ClientApp.LBAddr = removeUISuffix(tfOutputs.DC1DefaultPartition.ClientApp.LBAddr)
		tfOutputs.DC1Part1Partition.ClientApp.LBAddr = removeUISuffix(tfOutputs.DC1Part1Partition.ClientApp.LBAddr)
		tfOutputs.DC2DefaultPartition.ClientApp.LBAddr = removeUISuffix(tfOutputs.DC2DefaultPartition.ClientApp.LBAddr)

		logger.Log(t, "Setting up the Consul clients")
		consulClientOne, err := common.SetupConsulClient(t, tfOutputs.DC1ConsulServerAddr, common.WithToken(tfOutputs.DC1ConsulServerToken))
		require.NoError(t, err)

		consulClientTwo, err := common.SetupConsulClient(t, tfOutputs.DC2ConsulServerAddr, common.WithToken(tfOutputs.DC2ConsulServerToken))
		require.NoError(t, err)

		logger.Log(t, "Setting up ECS Client")
		ecsClient, err := common.NewECSClient(common.WithRegion(awsRegion))
		require.NoError(t, err)

		ensureAppsReadiness(t, consulClientOne, tfOutputs.DC1DefaultPartition)
		ensureAppsReadiness(t, consulClientOne, tfOutputs.DC1Part1Partition)
		ensureAppsReadiness(t, consulClientTwo, tfOutputs.DC2DefaultPartition)

		// Ensure that the gateways are also ready
		consulClientOne.EnsureServiceReadiness(fmt.Sprintf("%s-dc1-default-mesh-gateway", tfResName), nil)
		consulClientOne.EnsureServiceReadiness(fmt.Sprintf("%s-dc1-%s-mesh-gateway", tfResName, tfOutputs.DC1Part1Partition.Partition), &api.QueryOptions{Partition: tfOutputs.DC1Part1Partition.Partition})
		consulClientTwo.EnsureServiceReadiness(fmt.Sprintf("%s-dc2-mesh-gateway", tfResName), nil)

		// Begin actual validation
		clusterAppsList := []*PartitionDetails{
			tfOutputs.DC1DefaultPartition,
			tfOutputs.DC1Part1Partition,
			tfOutputs.DC2DefaultPartition,
		}

		var recordedUpstreamCalls map[string]string

		assertUpstreamCall := func(apps *PartitionDetails, expectedUpstream string) {
			recordedUpstream, ok := recordedUpstreamCalls[apps.getClientAppName()]
			require.True(t, ok)
			require.Equal(t, expectedUpstream, recordedUpstream)
		}

		// Without making any changes we expect calls from the client apps
		// to reach the server apps in their local partitions.
		logger.Log(t, "Calling upstreams from individual client tasks. Calls are expected to hit the local server instances in the same namespace as the client")
		recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
		assertUpstreamCall(tfOutputs.DC1DefaultPartition, tfOutputs.DC1DefaultPartition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC1Part1Partition, tfOutputs.DC1Part1Partition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC2DefaultPartition, tfOutputs.DC2DefaultPartition.getServerAppName())

		// Scaling down server app present in the default partition in DC1. After this, requests from
		// the client app in the default partition will failover to the server app present in
		// the part1 partition in DC1.
		mustScaleDownServerApp(t, ecsClient, consulClientOne, tfOutputs.DC1DefaultPartition)

		logger.Log(t, "Scale down complete. Calling upstreams for individual client tasks.")
		recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
		assertUpstreamCall(tfOutputs.DC1DefaultPartition, tfOutputs.DC1Part1Partition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC1Part1Partition, tfOutputs.DC1Part1Partition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC2DefaultPartition, tfOutputs.DC2DefaultPartition.getServerAppName())

		// Scaling down server app present in the part1 partition in DC1. After this,
		// the client apps present in the default and part1 partition will hit the server app present in
		// the default partition in DC2.
		mustScaleDownServerApp(t, ecsClient, consulClientOne, tfOutputs.DC1Part1Partition)

		logger.Log(t, "Scale down complete. Calling upstreams for individual client tasks.")
		recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
		assertUpstreamCall(tfOutputs.DC1DefaultPartition, tfOutputs.DC2DefaultPartition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC1Part1Partition, tfOutputs.DC2DefaultPartition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC2DefaultPartition, tfOutputs.DC2DefaultPartition.getServerAppName())

		// Scaling up server app present in the default partition in DC1. After this,
		// the client app in the default partition will hit the server app present in
		// the default partition in DC1. The client app in the part1 partition will also
		// hit the server app present in the default partition in DC1.
		mustScaleUpServerApp(t, ecsClient, consulClientOne, tfOutputs.DC1DefaultPartition)

		logger.Log(t, "Scale up complete. Calling upstreams for individual client tasks.")
		recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
		assertUpstreamCall(tfOutputs.DC1DefaultPartition, tfOutputs.DC1DefaultPartition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC1Part1Partition, tfOutputs.DC1DefaultPartition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC2DefaultPartition, tfOutputs.DC2DefaultPartition.getServerAppName())

		// Scaling down server app present in the default partition in DC2. After this,
		// the client app present in the default partition in DC2 will hit the server app present in
		// the default partition in DC1. The client app in the part1 partition should continue to
		// hit the server app present in the default partition in DC1.
		mustScaleDownServerApp(t, ecsClient, consulClientTwo, tfOutputs.DC2DefaultPartition)

		logger.Log(t, "Scale down complete. Calling upstreams for individual client tasks.")
		recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
		assertUpstreamCall(tfOutputs.DC1DefaultPartition, tfOutputs.DC1DefaultPartition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC1Part1Partition, tfOutputs.DC1DefaultPartition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC2DefaultPartition, tfOutputs.DC1DefaultPartition.getServerAppName())

		// Scaling up server app present in the part1 partition in DC1. After this,
		// the client app in the part1 partition will hit the server app present in
		// the part1 partition in DC1. The client app in the default partition will continue to
		// hit the server app present in the default partition in DC1.
		mustScaleUpServerApp(t, ecsClient, consulClientOne, tfOutputs.DC1Part1Partition)

		logger.Log(t, "Scale up complete. Calling upstreams for individual client tasks.")
		recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
		assertUpstreamCall(tfOutputs.DC1DefaultPartition, tfOutputs.DC1DefaultPartition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC1Part1Partition, tfOutputs.DC1Part1Partition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC2DefaultPartition, tfOutputs.DC1DefaultPartition.getServerAppName())

		// Scaling up server app present in the default partition in DC2. After this,
		// the client app present in the default partition in DC2 will hit the server app present in
		// the default partition in DC2. All the other client apps should hit their local server apps
		mustScaleUpServerApp(t, ecsClient, consulClientTwo, tfOutputs.DC2DefaultPartition)

		logger.Log(t, "Scale up complete. Calling upstreams for individual client tasks.")
		recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
		assertUpstreamCall(tfOutputs.DC1DefaultPartition, tfOutputs.DC1DefaultPartition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC1Part1Partition, tfOutputs.DC1Part1Partition.getServerAppName())
		assertUpstreamCall(tfOutputs.DC2DefaultPartition, tfOutputs.DC2DefaultPartition.getServerAppName())
	}
}

func ensureAppsReadiness(t *testing.T, consulClient *common.ConsulClientWrapper, partitionDetails *PartitionDetails) {
	logger.Log(t, fmt.Sprintf("checking if apps in %s partition & %s namespace are registered in Consul", partitionDetails.Partition, partitionDetails.Namespace))

	opts := &api.QueryOptions{
		Namespace: partitionDetails.Namespace,
		Partition: partitionDetails.Partition,
	}

	consulClient.EnsureServiceReadiness(partitionDetails.getClientAppConsulName(), opts)
	consulClient.EnsureServiceReadiness(partitionDetails.getServerAppConsulName(), opts)
}

func recordUpstreams(t *testing.T, apps []*PartitionDetails) map[string]string {
	upstreamCalls := make(map[string]string)
	for _, app := range apps {
		logger.Log(t, fmt.Sprintf("calling upstream for %s app in %s partition and %s cluster", app.getClientAppName(), app.Partition, app.ECSClusterARN))
		retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
			logger.Log(t, "hitting client app's load balancer to see if the server app is reachable")
			resp, err := common.GetFakeServiceResponse(app.getClientAppLBAddr())
			require.NoError(r, err)

			require.Equal(r, 200, resp.Code)
			require.Equal(r, "Hello World", resp.Body)
			require.NotNil(r, resp.UpstreamCalls)

			upstreamResp := resp.UpstreamCalls["http://localhost:1234"]
			require.NotNil(r, upstreamResp)
			require.Equal(r, 200, upstreamResp.Code)
			require.Equal(r, "Hello World", upstreamResp.Body)

			upstreamCalls[app.getClientAppName()] = upstreamResp.Name
		})
	}

	require.Len(t, upstreamCalls, 3)
	return upstreamCalls
}

func mustScaleUpServerApp(t *testing.T, ecsClient *common.ECSClientWrapper, consulClient *common.ConsulClientWrapper, apps *PartitionDetails) {
	logger.Log(t, fmt.Sprintf("Scaling up %s app in %s partition and %s namespace", apps.getServerAppConsulName(), apps.Partition, apps.Namespace))
	err := ecsClient.
		WithClusterARN(apps.ECSClusterARN).
		UpdateService(apps.getServerAppName(), 1)
	require.NoError(t, err)

	opts := &api.QueryOptions{
		Partition: apps.Partition,
		Namespace: apps.Namespace,
	}
	consulClient.EnsureServiceReadiness(apps.getServerAppConsulName(), opts)
}

func mustScaleDownServerApp(t *testing.T, ecsClient *common.ECSClientWrapper, consulClient *common.ConsulClientWrapper, apps *PartitionDetails) {
	logger.Log(t, fmt.Sprintf("Scaling down %s app in %s partition and %s namespace", apps.getServerAppConsulName(), apps.Partition, apps.Namespace))
	err := ecsClient.
		WithClusterARN(apps.ECSClusterARN).
		UpdateService(apps.getServerAppName(), 0)
	require.NoError(t, err)

	opts := &api.QueryOptions{
		Partition: apps.Partition,
		Namespace: apps.Namespace,
	}
	consulClient.EnsureServiceDeregistration(apps.getServerAppConsulName(), opts)
}
