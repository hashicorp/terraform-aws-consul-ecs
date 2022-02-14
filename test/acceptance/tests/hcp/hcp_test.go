package hcp

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	terratestLogger "github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/helpers"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

func TestHCP(t *testing.T) {
	randomSuffix := strings.ToLower(random.UniqueId())
	tfVars := suite.Config().TFVars()
	tfVars["suffix"] = randomSuffix
	tfOptions := &terraform.Options{
		TerraformDir: "./terraform/hcp-install",
		Vars:         tfVars,
		NoColor:      true,
	}
	terraformOptions := terraform.WithDefaultRetryableErrors(t, tfOptions)

	defer func() {
		if suite.Config().NoCleanupOnFailure && t.Failed() {
			logger.Log(t, "skipping resource cleanup because -no-cleanup-on-failure=true")
		} else {
			terraform.Destroy(t, terraformOptions)
		}
	}()
	terraform.InitAndApply(t, terraformOptions)

	outputs := terraform.OutputAll(t, &terraform.Options{
		TerraformDir: "./terraform/hcp-install",
		NoColor:      true,
		Logger:       terratestLogger.Discard,
	})

	cfg := api.DefaultConfig()
	cfg.Address = outputs["hcp_public_endpoint"].(string)
	cfg.Token = outputs["token"].(string)
	consulClient, err := api.NewClient(cfg)
	require.NoError(t, err)

	serverServiceName := fmt.Sprintf("test_server_%s", randomSuffix)
	clientServiceName := fmt.Sprintf("test_client_%s", randomSuffix)

	// Wait for both tasks to be registered in Consul.
	logger.Log(t, "checking if services are registered")
	retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		services, _, err := consulClient.Catalog().Services(nil)
		r.Check(err)
		logger.Logf(t, "Consul services: %v", services)
		require.Contains(r, services, serverServiceName)
		require.Contains(r, services, clientServiceName)
	})

	// Wait for passing health check for test_server.
	logger.Log(t, "waiting for health checks of the test_server")
	retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		checks, _, err := consulClient.Health().Checks(serverServiceName, nil)
		r.Check(err)
		logger.Logf(t, "health checks: %v", checks)
		require.Len(r, checks, 1)
		require.Equal(r, checks[0].Status, api.HealthPassing)
	})

	// Use aws exec to curl between the apps.
	taskListOut := shell.RunCommandAndGetOutput(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"list-tasks",
			"--region",
			suite.Config().Region,
			"--cluster",
			suite.Config().ECSClusterARN,
			"--family",
			clientServiceName,
		},
	})

	var tasks listTasksResponse
	require.NoError(t, json.Unmarshal([]byte(taskListOut), &tasks))
	require.Len(t, tasks.TaskARNs, 1)

	// First check that connection between apps is unsuccessful without an intention.
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		curlOut, err := helpers.ExecuteRemoteCommand(t, suite.Config(), tasks.TaskARNs[0], "basic", `/bin/sh -c "curl localhost:1234"`)
		r.Check(err)
		if !strings.Contains(curlOut, `curl: (52) Empty reply from server`) {
			r.Errorf("response was unexpected: %q", curlOut)
		}
	})

	// Create an intention.
	retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		_, err := consulClient.Connect().IntentionUpsert(&api.Intention{
			SourceName:      clientServiceName,
			DestinationName: serverServiceName,
			Action:          api.IntentionActionAllow,
		}, nil)
		r.Check(err)
	})

	// Now check that the connection succeeds.
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		curlOut, err := helpers.ExecuteRemoteCommand(t, suite.Config(), tasks.TaskARNs[0], "basic", `/bin/sh -c "curl localhost:1234"`)
		r.Check(err)
		if !strings.Contains(curlOut, `"code": 200`) {
			r.Errorf("response was unexpected: %q", curlOut)
		}
	})

	// TODO: The token deletion check is disabled due to a race condition.
	// If the service still exists in Consul after a Task stops, the controller skips
	// token deletion. This avoids removing tokens that are still in use, but it means it
	// may never delete a token depending on the timing of consul-client shutting down and
	// the polling interval of the controller.
	//
	// Check that the ACL tokens for services are deleted
	// when services are destroyed.
	//if secure {
	//	// First, destroy just the service mesh services.
	//	tfOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
	//		TerraformDir: "./terraform/basic-install",
	//		Vars:         tfVars,
	//		NoColor:      true,
	//		Targets: []string{
	//			"aws_ecs_service.test_server",
	//			"aws_ecs_service.test_client",
	//			"module.test_server",
	//			"module.test_client",
	//		},
	//	})
	//	terraform.Destroy(t, tfOptions)
	//
	//	// Check that the ACL tokens are deleted from Consul.
	//	retry.RunWith(&retry.Timer{Timeout: 5 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
	//		out, err := executeRemoteCommand(t, consulServerTaskARN, "consul-server", `/bin/sh -c "consul acl token list"`)
	//		require.NoError(r, err)
	//		require.NotContains(r, out, fmt.Sprintf("test_client_%s", randomSuffix))
	//		require.NotContains(r, out, fmt.Sprintf("test_server_%s", randomSuffix))
	//	})
	//}

	logger.Log(t, "Test successful!")
}

// TestNamespaces ensures that services in different namespaces can be
// can be configured to communicate.
func TestNamespaces(t *testing.T) {
	randomSuffix := strings.ToLower(random.UniqueId())
	const clientServiceNS = "ns1"
	const serverServiceNS = "ns2"
	tfVars := suite.Config().TFVars()
	tfVars["suffix"] = randomSuffix
	tfVars["test_client_ns"] = clientServiceNS
	tfVars["test_server_ns"] = serverServiceNS
	tfOptions := &terraform.Options{
		TerraformDir: "./terraform/ns",
		Vars:         tfVars,
		NoColor:      true,
	}
	terraformOptions := terraform.WithDefaultRetryableErrors(t, tfOptions)

	defer func() {
		if suite.Config().NoCleanupOnFailure && t.Failed() {
			logger.Log(t, "skipping resource cleanup because -no-cleanup-on-failure=true")
		} else {
			terraform.Destroy(t, terraformOptions)
		}
	}()
	terraform.InitAndApply(t, terraformOptions)

	outputs := terraform.OutputAll(t, &terraform.Options{
		TerraformDir: "./terraform/ns",
		NoColor:      true,
		Logger:       terratestLogger.Discard,
	})

	cfg := api.DefaultConfig()
	cfg.Address = outputs["hcp_public_endpoint"].(string)
	cfg.Token = outputs["token"].(string)
	consulClient, err := api.NewClient(cfg)
	require.NoError(t, err)

	serverServiceName := fmt.Sprintf("test_server_%s", randomSuffix)
	clientServiceName := fmt.Sprintf("test_client_%s", randomSuffix)

	// Wait for both tasks to be registered in Consul.
	logger.Log(t, "checking if services are registered")
	retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		services, _, err := consulClient.Catalog().Services(nil)
		r.Check(err)
		logger.Logf(t, "Consul services: %v", services)
		require.Contains(r, services, serverServiceName)
		require.Contains(r, services, clientServiceName)
	})

	// Wait for passing health check for test_server.
	logger.Log(t, "waiting for health checks of the test_server")
	retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		checks, _, err := consulClient.Health().Checks(serverServiceName, nil)
		r.Check(err)
		logger.Logf(t, "health checks: %v", checks)
		require.Len(r, checks, 1)
		require.Equal(r, checks[0].Status, api.HealthPassing)
	})

	// Use aws exec to curl between the apps.
	taskListOut := shell.RunCommandAndGetOutput(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"list-tasks",
			"--region",
			suite.Config().Region,
			"--cluster",
			suite.Config().ECSClusterARN,
			"--family",
			clientServiceName,
		},
	})

	var tasks listTasksResponse
	require.NoError(t, json.Unmarshal([]byte(taskListOut), &tasks))
	require.Len(t, tasks.TaskARNs, 1)

	// First check that connection between apps is unsuccessful without an intention.
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		curlOut, err := helpers.ExecuteRemoteCommand(t, suite.Config(), tasks.TaskARNs[0], "basic", `/bin/sh -c "curl localhost:1234"`)
		r.Check(err)
		if !strings.Contains(curlOut, `curl: (52) Empty reply from server`) {
			r.Errorf("response was unexpected: %q", curlOut)
		}
	})

	// Create an intention.
	retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		_, err := consulClient.Connect().IntentionUpsert(&api.Intention{
			SourceNS:        clientServiceNS,
			SourceName:      clientServiceName,
			DestinationNS:   serverServiceNS,
			DestinationName: serverServiceName,
			Action:          api.IntentionActionAllow,
		}, nil)
		r.Check(err)
	})

	// Now check that the connection succeeds.
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		curlOut, err := helpers.ExecuteRemoteCommand(t, suite.Config(), tasks.TaskARNs[0], "basic", `/bin/sh -c "curl localhost:1234"`)
		r.Check(err)
		if !strings.Contains(curlOut, `"code": 200`) {
			r.Errorf("response was unexpected: %q", curlOut)
		}
	})

	logger.Log(t, "Test successful!")
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}
