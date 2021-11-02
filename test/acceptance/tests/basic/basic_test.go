package basic

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/helpers"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

// Test the validation that if TLS is enabled, Consul's CA certificate must also be provided.
func TestValidation_CACertRequiredIfTLSIsEnabled(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/ca-cert-validate",
		NoColor:      true,
	})
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	_, err := terraform.InitAndPlanE(t, terraformOptions)
	require.Error(t, err)
	require.Contains(t, err.Error(), "ERROR: consul_server_ca_cert_arn must be set if tls is true")
}

// Test the validation that if ACLs are enabled, Consul client token must also be provided.
func TestValidation_ConsulClientTokenIsRequiredIfACLsIsEnabled(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/consul-client-token-validate",
		NoColor:      true,
	})
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	_, err := terraform.InitAndPlanE(t, terraformOptions)
	require.Error(t, err)
	require.Contains(t, err.Error(), "ERROR: consul_client_token_secret_arn must be set if acls is true")
}

// Test the validation that if ACLs are enabled, ACL secret name prefix must also be provided.
func TestValidation_ACLSecretNamePrefixIsRequiredIfACLsIsEnabled(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/acl-secret-name-prefix-validate",
		NoColor:      true,
	})
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	_, err := terraform.InitAndPlanE(t, terraformOptions)
	require.Error(t, err)
	require.Contains(t, err.Error(), "ERROR: acl_secret_name_prefix must be set if acls is true")
}

func TestBasic(t *testing.T) {
	randomSuffix := strings.ToLower(random.UniqueId())
	tfVars := suite.Config().TFVars("route_table_ids")
	tfVars["suffix"] = randomSuffix
	serverServiceName := "custom_test_server"
	// This uses the explicitly passed service name rather than the task's family name.
	tfVars["server_service_name"] = serverServiceName
	clientServiceName := "test_client"

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/basic-install",
		Vars:         tfVars,
		NoColor:      true,
	})

	t.Cleanup(func() {
		if suite.Config().NoCleanupOnFailure && t.Failed() {
			logger.Log(t, "skipping resource cleanup because -no-cleanup-on-failure=true")
		} else {
			terraform.Destroy(t, terraformOptions)
		}
	})

	terraform.InitAndApply(t, terraformOptions)

	// Wait for consul server to be up.
	var consulServerTaskARN string
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		taskListOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
			Command: "aws",
			Args: []string{
				"ecs",
				"list-tasks",
				"--region",
				suite.Config().Region,
				"--cluster",
				suite.Config().ECSClusterARN,
				"--family",
				fmt.Sprintf("consul_server_%s", randomSuffix),
			},
		})
		r.Check(err)

		var tasks listTasksResponse
		r.Check(json.Unmarshal([]byte(taskListOut), &tasks))
		if len(tasks.TaskARNs) != 1 {
			r.Errorf("expected 1 task, got %d", len(tasks.TaskARNs))
			return
		}

		consulServerTaskARN = tasks.TaskARNs[0]
	})

	// Wait for both tasks to be registered in Consul.
	retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		out, err := helpers.ExecuteRemoteCommand(t, suite.Config(), consulServerTaskARN, "consul-server", `/bin/sh -c "consul catalog services"`)
		r.Check(err)
		if !strings.Contains(out, fmt.Sprintf("%s_%s", serverServiceName, randomSuffix)) ||
			!strings.Contains(out, fmt.Sprintf("%s_%s", clientServiceName, randomSuffix)) {
			r.Errorf("services not yet registered, got %q", out)
		}
	})

	// Wait for passing health check for `serverServiceName` and `clientServiceName`.
	// `serverServiceName` has a Consul native HTTP check.
	// `clientServiceName`  has a check synced from ECS.
	services := []string{serverServiceName, clientServiceName}
	for _, serviceName := range services {
		retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
			out, err := helpers.ExecuteRemoteCommand(
				t,
				suite.Config(),
				consulServerTaskARN,
				"consul-server",
				fmt.Sprintf(`/bin/sh -c 'curl localhost:8500/v1/health/checks/%s_%s'`, serviceName, randomSuffix),
			)
			r.Check(err)

			statusRegex := regexp.MustCompile(`"Status"\s*:\s*"passing"`)
			if statusRegex.FindAllString(out, 1) == nil {
				r.Errorf("Check status not yet passing")
			}
		})
	}

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
			fmt.Sprintf("test_client_%s", randomSuffix),
		},
	})

	var tasks listTasksResponse
	require.NoError(t, json.Unmarshal([]byte(taskListOut), &tasks))
	require.Len(t, tasks.TaskARNs, 1)
	testClientTaskARN := tasks.TaskARNs[0]
	arnParts := strings.Split(testClientTaskARN, "/")
	testClientTaskID := arnParts[len(arnParts)-1]

	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		curlOut, err := helpers.ExecuteRemoteCommand(t, suite.Config(), tasks.TaskARNs[0], "basic", `/bin/sh -c "curl localhost:1234"`)
		r.Check(err)
		if !strings.Contains(curlOut, `"code": 200`) {
			r.Errorf("response was unexpected: %q", curlOut)
		}
	})

	// Validate graceful shutdown behavior. We check the client app can reach its upstream after the task is stopped.
	// This relies on a couple of helpers:
	// * a custom entrypoint for the client app that keeps it running for 10s into Task shutdown, and
	// * an additional "shutdown-monitor" container that makes requests to the client app
	// Since this is timing dependent, we check logs after the fact to validate when the containers exited.
	shell.RunCommandAndGetOutput(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"stop-task",
			"--region", suite.Config().Region,
			"--cluster", suite.Config().ECSClusterARN,
			"--task", testClientTaskARN,
			"--reason", "Stopped to validate graceful shutdown in acceptance tests",
		},
	})

	// Wait for the task to stop (~30 seconds)
	retry.RunWith(&retry.Timer{Timeout: 1 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		describeTasksOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
			Command: "aws",
			Args: []string{
				"ecs",
				"describe-tasks",
				"--region", suite.Config().Region,
				"--cluster", suite.Config().ECSClusterARN,
				"--task", testClientTaskARN,
			},
		})
		r.Check(err)

		var describeTasks ecs.DescribeTasksOutput
		r.Check(json.Unmarshal([]byte(describeTasksOut), &describeTasks))
		require.Len(r, describeTasks.Tasks, 1)
		require.NotEqual(r, "RUNNING", describeTasks.Tasks[0].LastStatus)
	})

	// Check logs to see that the application ignored the TERM signal and exited about 10s later.
	retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
		appLogs, err := helpers.GetCloudWatchLogEvents(t, suite.Config(),
			fmt.Sprintf("test_client_%s/basic/%s", randomSuffix, testClientTaskID),
		)
		require.NoError(r, err)

		appLogs = appLogs.Filter("TEST LOG:")
		require.Len(r, appLogs, 2)
		require.Equal(r, appLogs[0].Message, "TEST LOG: Caught sigterm. Sleeping 10s...")
		require.Equal(r, appLogs[1].Message, "TEST LOG: on exit")
		require.InDelta(r, 10, appLogs.Duration().Seconds(), 1)
	})

	// Check that the Envoy entrypoint received the sigterm.
	retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
		envoyLogs, err := helpers.GetCloudWatchLogEvents(t, suite.Config(),
			fmt.Sprintf("test_client_%s/sidecar-proxy/%s", randomSuffix, testClientTaskID),
		)
		require.NoError(r, err)

		logMsg := "consul-ecs: waiting for application container(s) to stop"
		envoyLogs = envoyLogs.Filter(logMsg)
		require.GreaterOrEqual(r, len(envoyLogs), 1)
		require.Contains(r, envoyLogs[0].Message, logMsg)
	})

	// Retrieve "shutdown-monitor" logs to check outgoing requests succeeded.
	retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
		monitorLogs, err := helpers.GetCloudWatchLogEvents(t, suite.Config(),
			fmt.Sprintf("test_client_%s/shutdown-monitor/%s", randomSuffix, testClientTaskID))
		require.NoError(r, err)

		// Check how long after shutdown the upstream was reachable.
		upstreamOkLogs := monitorLogs.Filter(
			"Signal received: signal=terminated",
			"upstream: [OK] GET http://localhost:1234 (200)",
		)
		// The client app is configured to run for about 10 seconds after Task shutdown.
		require.GreaterOrEqual(r, len(upstreamOkLogs.Filter("upstream: [OK]")), 7)
		require.GreaterOrEqual(r, upstreamOkLogs.Duration().Seconds(), 8.0)

		// Double-check the application was still functional for about 10 seconds into Task shutdown.
		// The FakeService makes requests to the upstream, so this further validates Envoy allows outgoing requests.
		applicationOkLogs := monitorLogs.Filter(
			"Signal received: signal=terminated",
			"application: [OK] GET http://localhost:9090 (200)",
		)
		require.GreaterOrEqual(r, len(applicationOkLogs.Filter("application: [OK]")), 7)
		require.GreaterOrEqual(r, applicationOkLogs.Duration().Seconds(), 8.0)
	})

	logger.Log(t, "Test successful!")
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}
