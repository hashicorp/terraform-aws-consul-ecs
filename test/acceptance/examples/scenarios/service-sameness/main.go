// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package sameness

import (
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/serf/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/common"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type sameness struct {
	name string
}

type apps struct {
	partition  string
	namespace  string
	clusterARN string
	region     string
	client     app
	server     app
}

type app struct {
	name              string
	consulServiceName string
	lbAddr            string
}

func New(name string) scenarios.Scenario {
	return &sameness{
		name: "same",
	}
}

func (s *sameness) GetFolderName() string {
	return "service-sameness"
}

func (s *sameness) GetTerraformVars() (map[string]interface{}, error) {
	vars := map[string]interface{}{
		"region": "us-west-1",
		"name":   s.name,
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

func (s *sameness) Validate(t *testing.T, outputVars map[string]interface{}) {
	logger.Log(t, "Fetching required output terraform variables")
	getOutputVariableValue := func(name string) string {
		val, ok := outputVars[name].(string)
		require.True(t, ok)
		return val
	}

	dc1ConsulServerURL := getOutputVariableValue("dc1_server_url")
	dc2ConsulServerURL := getOutputVariableValue("dc2_server_url")
	dc1ConsulServerToken := getOutputVariableValue("dc1_server_bootstrap_token")
	dc2ConsulServerToken := getOutputVariableValue("dc2_server_bootstrap_token")

	dc1DefaultPartitionApps := getAppDetails(t, "dc1_default_partition_apps", outputVars)
	dc1Part1PartitionApps := getAppDetails(t, "dc1_part1_partition_apps", outputVars)
	dc2DefaultPartitionApps := getAppDetails(t, "dc2_default_partition_apps", outputVars)

	logger.Log(t, "Setting up the Consul clients")
	consulClientOne, err := common.SetupConsulClient(dc1ConsulServerURL, dc1ConsulServerToken)
	require.NoError(t, err)

	consulClientTwo, err := common.SetupConsulClient(dc2ConsulServerURL, dc2ConsulServerToken)
	require.NoError(t, err)

	logger.Log(t, "Setting up ECS Client")
	ecsClient, err := common.NewECSClient()
	require.NoError(t, err)

	ensureAppsReadiness(t, consulClientOne, dc1DefaultPartitionApps)
	ensureAppsReadiness(t, consulClientOne, dc1Part1PartitionApps)
	ensureAppsReadiness(t, consulClientTwo, dc2DefaultPartitionApps)

	// Ensure that the gateways are also ready
	ensureServiceReadiness(t, consulClientOne, fmt.Sprintf("%s-dc1-default-mesh-gateway", s.name), nil)
	ensureServiceReadiness(t, consulClientOne, fmt.Sprintf("%s-dc1-%s-mesh-gateway", s.name, dc1Part1PartitionApps.partition), &api.QueryOptions{Partition: dc1DefaultPartitionApps.partition})
	ensureServiceReadiness(t, consulClientTwo, fmt.Sprintf("%s-dc2-default-mesh-gateway", s.name), nil)

	// Begin actual validation
	clusterAppsList := []*apps{
		dc1DefaultPartitionApps,
		dc1Part1PartitionApps,
		dc2DefaultPartitionApps,
	}

	var recordedUpstreamCalls map[string]string

	assertUpstreamCall := func(apps *apps, expectedUpstream string) {
		recordedUpstream, ok := recordedUpstreamCalls[apps.getClientAppName()]
		require.True(t, ok)
		require.Equal(t, expectedUpstream, recordedUpstream)
	}

	// Without making any changes we expect calls from the client apps
	// to reach the server apps in their local partitions.
	logger.Log(t, "Calling upstreams from individual client tasks. Calls are expected to hit the local server instances in the same namespace as the client")
	recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
	assertUpstreamCall(dc1DefaultPartitionApps, dc1DefaultPartitionApps.getServerAppName())
	assertUpstreamCall(dc1Part1PartitionApps, dc1Part1PartitionApps.getServerAppName())
	assertUpstreamCall(dc2DefaultPartitionApps, dc2DefaultPartitionApps.getServerAppName())

	// Scaling down server app present in the default partition in DC1. After this, requests from
	// the client app in the default partition will failover to the server app present in
	// the part1 partition in DC1.
	mustScaleDownServerApp(t, ecsClient, consulClientOne, dc1DefaultPartitionApps)

	logger.Log(t, "Scale down complete. Calling upstreams for individual client tasks.")
	recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
	assertUpstreamCall(dc1DefaultPartitionApps, dc1Part1PartitionApps.getServerAppName())
	assertUpstreamCall(dc1Part1PartitionApps, dc1Part1PartitionApps.getServerAppName())
	assertUpstreamCall(dc2DefaultPartitionApps, dc2DefaultPartitionApps.getServerAppName())

	// Scaling down server app present in the part1 partition in DC1. After this,
	// the client apps present in the default and part1 partition will hit the server app present in
	// the default partition in DC2.
	mustScaleDownServerApp(t, ecsClient, consulClientOne, dc1Part1PartitionApps)

	logger.Log(t, "Scale down complete. Calling upstreams for individual client tasks.")
	recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
	assertUpstreamCall(dc1DefaultPartitionApps, dc2DefaultPartitionApps.getServerAppName())
	assertUpstreamCall(dc1Part1PartitionApps, dc2DefaultPartitionApps.getServerAppName())
	assertUpstreamCall(dc2DefaultPartitionApps, dc2DefaultPartitionApps.getServerAppName())

	// Scaling up server app present in the default partition in DC1. After this,
	// the client app in the default partition will hit the server app present in
	// the default partition in DC1. The client app in the part1 partition will also
	// hit the server app present in the default partition in DC1.
	mustScaleUpServerApp(t, ecsClient, consulClientOne, dc1DefaultPartitionApps)

	logger.Log(t, "Scale up complete. Calling upstreams for individual client tasks.")
	recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
	assertUpstreamCall(dc1DefaultPartitionApps, dc1DefaultPartitionApps.getServerAppName())
	assertUpstreamCall(dc1Part1PartitionApps, dc1DefaultPartitionApps.getServerAppName())
	assertUpstreamCall(dc2DefaultPartitionApps, dc2DefaultPartitionApps.getServerAppName())

	// Scaling down server app present in the default partition in DC2. After this,
	// the client app present in the default partition in DC2 will hit the server app present in
	// the default partition in DC1. The client app in the part1 partition should continue to
	// hit the server app present in the default partition in DC1.
	mustScaleDownServerApp(t, ecsClient, consulClientTwo, dc2DefaultPartitionApps)

	logger.Log(t, "Scale down complete. Calling upstreams for individual client tasks.")
	recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
	assertUpstreamCall(dc1DefaultPartitionApps, dc1DefaultPartitionApps.getServerAppName())
	assertUpstreamCall(dc1Part1PartitionApps, dc1DefaultPartitionApps.getServerAppName())
	assertUpstreamCall(dc2DefaultPartitionApps, dc1DefaultPartitionApps.getServerAppName())

	// Scaling up server app present in the part1 partition in DC1. After this,
	// the client app in the part1 partition will hit the server app present in
	// the part1 partition in DC1. The client app in the default partition will continue to
	// hit the server app present in the default partition in DC1.
	mustScaleUpServerApp(t, ecsClient, consulClientOne, dc1Part1PartitionApps)

	logger.Log(t, "Scale up complete. Calling upstreams for individual client tasks.")
	recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
	assertUpstreamCall(dc1DefaultPartitionApps, dc1DefaultPartitionApps.getServerAppName())
	assertUpstreamCall(dc1Part1PartitionApps, dc1Part1PartitionApps.getServerAppName())
	assertUpstreamCall(dc2DefaultPartitionApps, dc1DefaultPartitionApps.getServerAppName())

	// Scaling up server app present in the default partition in DC2. After this,
	// the client app present in the default partition in DC2 will hit the server app present in
	// the default partition in DC2. All the other client apps should hit their local server apps
	mustScaleUpServerApp(t, ecsClient, consulClientTwo, dc2DefaultPartitionApps)

	logger.Log(t, "Scale up complete. Calling upstreams for individual client tasks.")
	recordedUpstreamCalls = recordUpstreams(t, clusterAppsList)
	assertUpstreamCall(dc1DefaultPartitionApps, dc1DefaultPartitionApps.getServerAppName())
	assertUpstreamCall(dc1Part1PartitionApps, dc1Part1PartitionApps.getServerAppName())
	assertUpstreamCall(dc2DefaultPartitionApps, dc2DefaultPartitionApps.getServerAppName())
}

func (a *apps) getClientAppName() string {
	return a.client.name
}

func (a *apps) getServerAppName() string {
	return a.server.name
}

func (a *apps) getServerAppConsulName() string {
	return a.server.consulServiceName
}

func getAppDetails(t *testing.T, name string, outputVars map[string]interface{}) *apps {
	val, ok := outputVars[name].(map[string]interface{})
	require.True(t, ok)

	ensureAndReturnNonEmptyVal := func(v interface{}) string {
		require.NotEmpty(t, v)
		return v.(string)
	}

	clientAppVal := val["client"].(map[string]interface{})
	require.NotEmpty(t, clientAppVal)

	client := app{
		name:              ensureAndReturnNonEmptyVal(clientAppVal["name"]),
		consulServiceName: ensureAndReturnNonEmptyVal(clientAppVal["consul_service_name"]),
		lbAddr:            ensureAndReturnNonEmptyVal(clientAppVal["lb_address"]),
	}

	serverAppVal := val["server"].(map[string]interface{})
	require.NotEmpty(t, serverAppVal)
	server := app{
		name:              ensureAndReturnNonEmptyVal(serverAppVal["name"]),
		consulServiceName: ensureAndReturnNonEmptyVal(serverAppVal["consul_service_name"]),
	}

	return &apps{
		partition:  ensureAndReturnNonEmptyVal(val["partition"]),
		namespace:  ensureAndReturnNonEmptyVal(val["namespace"]),
		clusterARN: ensureAndReturnNonEmptyVal(val["ecs_cluster_arn"]),
		region:     ensureAndReturnNonEmptyVal(val["region"]),
		client:     client,
		server:     server,
	}
}

func ensureAppsReadiness(t *testing.T, consulClient *api.Client, appDetails *apps) {
	logger.Log(t, fmt.Sprintf("checking if apps in %s partition & %s namespace are registered in Consul", appDetails.partition, appDetails.namespace))

	opts := &api.QueryOptions{
		Namespace: appDetails.namespace,
		Partition: appDetails.partition,
	}

	ensureServiceReadiness(t, consulClient, appDetails.client.consulServiceName, opts)
	ensureServiceReadiness(t, consulClient, appDetails.server.consulServiceName, opts)
}

func ensureServiceReadiness(t *testing.T, client *api.Client, name string, opts *api.QueryOptions) {
	ensureServiceRegistration(t, client, name, opts)
	ensureHealthyService(t, client, name, opts)
}

func ensureServiceRegistration(t *testing.T, consulClient *api.Client, name string, opts *api.QueryOptions) {
	logger.Log(t, fmt.Sprintf("checking if service %s is registered in Consul", name))
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		exists, err := common.ServiceExists(consulClient, name, opts)
		require.NoError(r, err)
		require.True(r, exists)
	})
}

func ensureServiceDeregistration(t *testing.T, consulClient *api.Client, name string, opts *api.QueryOptions) {
	logger.Log(t, fmt.Sprintf("checking if service %s is deregistered in Consul", name))
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		exists, err := common.ServiceExists(consulClient, name, opts)
		require.NoError(r, err)
		require.False(r, exists)
	})
}

func ensureHealthyService(t *testing.T, consulClient *api.Client, name string, opts *api.QueryOptions) {
	logger.Log(t, fmt.Sprintf("checking if all instances of %s are healthy", name))
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		healthy, err := common.IsServiceHealthy(consulClient, name, opts)
		require.NoError(r, err)
		require.True(r, healthy)
	})
}

func recordUpstreams(t *testing.T, apps []*apps) map[string]string {
	upstreamCalls := make(map[string]string)
	for _, app := range apps {
		logger.Log(t, "calling upstream for apps in %s partition and %s cluster", app.partition, app.clusterARN)
		retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
			logger.Log(t, "hitting client app's load balancer to see if the server app is reachable")
			resp, err := common.GetFakeServiceResponse(app.client.lbAddr)
			require.NoError(r, err)

			require.Equal(r, 200, resp.Code)
			require.Equal(r, "Hello World", resp.Body)
			require.NotNil(r, resp.UpstreamCalls)

			upstreamResp := resp.UpstreamCalls["http://localhost:1234"]
			require.NotNil(r, upstreamResp)
			require.Equal(r, 200, upstreamResp.Code)
			require.Equal(r, "Hello World", upstreamResp.Body)

			upstreamCalls[app.client.name] = upstreamResp.Name
		})
	}

	require.Len(t, upstreamCalls, 3)
	return upstreamCalls
}

func mustScaleUpServerApp(t *testing.T, ecsClient *common.ECSClientWrapper, consulClient *api.Client, apps *apps) {
	logger.Log(t, fmt.Sprintf("Scaling up %s app in %s partition and %s namespace", apps.getServerAppConsulName(), apps.partition, apps.namespace))
	err := ecsClient.
		WithClusterARN(apps.clusterARN).
		UpdateService(apps.getServerAppName(), 1)
	require.NoError(t, err)

	opts := &api.QueryOptions{
		Partition: apps.partition,
		Namespace: apps.namespace,
	}
	ensureServiceReadiness(t, consulClient, apps.getServerAppConsulName(), opts)
}

func mustScaleDownServerApp(t *testing.T, ecsClient *common.ECSClientWrapper, consulClient *api.Client, apps *apps) {
	logger.Log(t, fmt.Sprintf("Scaling down %s app in %s partition and %s namespace", apps.getServerAppConsulName(), apps.partition, apps.namespace))
	err := ecsClient.
		WithClusterARN(apps.clusterARN).
		UpdateService(apps.getServerAppName(), 0)
	require.NoError(t, err)

	opts := &api.QueryOptions{
		Partition: apps.partition,
		Namespace: apps.namespace,
	}
	ensureServiceDeregistration(t, consulClient, apps.getServerAppConsulName(), opts)
}
