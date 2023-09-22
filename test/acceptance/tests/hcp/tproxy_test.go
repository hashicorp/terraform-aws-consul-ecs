// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package hcp

import (
	"fmt"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/helpers"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

// TestNamespacesTProxy ensures that services in different namespaces can be
// can be configured to communicate with transparent proxy enabled
func TestNamespacesTProxy(t *testing.T) {
	cfg := parseHCPTestConfig(t)
	checkAndSkipTest(t, cfg.LaunchType)

	// generate input variables to the test terraform using the config.
	ignoreVars := []string{"token", "enable_hcp", "consul_version", "retry_join", "consul_public_endpoint_url"}
	tfVars := TFVars(cfg, ignoreVars...)

	consulClient, initialConsulState, err := consulClient(t, cfg.ConsulAddr, cfg.ConsulToken)
	require.NoError(t, err)
	t.Cleanup(func() {
		if err := restoreConsulState(t, consulClient, initialConsulState); err != nil {
			logger.Log(t, "failed to restore Consul state:", err)
		}
	})

	randomSuffix := strings.ToLower(random.UniqueId())

	taskConfig := helpers.MeshTaskConfig{
		ConsulClient: consulClient,
		Region:       cfg.Region,
		ClusterARN:   cfg.ECSClusterARNs[0],
		Partition:    "default",
	}

	taskConfig.Name = fmt.Sprintf("test_client_%s", randomSuffix)
	taskConfig.Namespace = "ns1"
	clientTask := helpers.NewMeshTask(t, taskConfig)

	taskConfig.Name = fmt.Sprintf("test_server_%s", randomSuffix)
	taskConfig.Namespace = "ns2"
	serverTask := helpers.NewMeshTask(t, taskConfig)

	tfVars["suffix"] = randomSuffix
	tfVars["client_namespace"] = clientTask.Namespace
	tfVars["server_namespace"] = serverTask.Namespace
	tfVars["consul_image"] = cfg.ConsulImageURI(true)
	tfVars["consul_server_address"] = cfg.getServerAddress()

	terraformOptions, _ := terraformInitAndApply(t, "./terraform/ns-tproxy", tfVars)
	t.Cleanup(func() { terraformDestroy(t, terraformOptions, suite.Config().NoCleanupOnFailure) })

	// Wait for both tasks to be registered in Consul.
	waitForTasks(t, clientTask, serverTask)

	curlCommand := fmt.Sprintf(`/bin/sh -c "curl http://%s.service.%s.ns.consul"`, serverTask.Name, serverTask.Namespace)

	// Check that the connection between apps is unsuccessful without an intention.
	logger.Log(t, "checking that the connection between apps is unsuccessful without an intention")
	expectCurlOutput(t, clientTask, curlCommand, `curl: (52) Empty reply from server`)

	// Create an intention.
	upsertIntention(t, consulClient, api.IntentionActionAllow, clientTask, serverTask)
	t.Cleanup(func() { deleteIntention(t, consulClient, serverTask) })

	// Now check that the connection succeeds.
	logger.Log(t, "checking that the connection succeeds with an intention")
	expectCurlOutput(t, clientTask, curlCommand, `"code": 200`)

	logger.Log(t, "Test successful!")
}

func checkAndSkipTest(t *testing.T, ecsLaunchType string) {
	if ecsLaunchType != "EC2" {
		t.Skip("TestTransparentProxy requires EC2 launch type for ECS.")
	}
}
