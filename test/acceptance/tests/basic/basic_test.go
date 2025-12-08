// Copyright IBM Corp. 2021, 2025
// SPDX-License-Identifier: MPL-2.0

package basic

import (
	"fmt"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/helpers"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

func TestBasic(t *testing.T) {
	t.Parallel()

	cases := []struct {
		secure        bool
		enterprise    bool
		stateFile     string
		ecsClusterARN string
		datacenter    string
	}{
		{secure: false},
		{secure: true},
		{secure: true, enterprise: true},
	}

	cfg := suite.Config()
	require.GreaterOrEqual(t, len(cfg.ECSClusterARNs), len(cases),
		"TestBasic requires %d ECS clusters. Update setup-terraform and re-run.", len(cases),
	)

	initOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/basic-install",
		NoColor:      true,
	})
	terraform.Init(t, initOptions)

	for i, c := range cases {
		c := c

		// To support running in parallel, each test case should have:
		// - a unique cluster
		// - a unique Terrform state file to isolate resources
		// - a unique datacenter within the VPC to avoid conflicts in CloudMap namespaces
		// If more clusters are needed, update the cluster count in setup-terraform
		c.ecsClusterARN = cfg.ECSClusterARNs[i]
		c.datacenter = fmt.Sprintf("dc%d", i)
		c.stateFile = fmt.Sprintf("terraform-%d.tfstate", i)

		t.Run(fmt.Sprintf("secure: %t,enterprise: %t", c.secure, c.enterprise), func(t *testing.T) {
			t.Parallel()

			randomSuffix := strings.ToLower(random.UniqueId())

			tfEnvVars := map[string]string{
				// Use a unique state file for each parallel invocation of Terraform.
				"TF_CLI_ARGS": fmt.Sprintf("-state=%s -state-out=%s", c.stateFile, c.stateFile),
			}

			tfVars := cfg.TFVars("route_table_ids", "ecs_cluster_arns")
			tfVars["secure"] = c.secure
			tfVars["suffix"] = randomSuffix
			tfVars["ecs_cluster_arn"] = c.ecsClusterARN
			tfVars["consul_datacenter"] = c.datacenter
			clientServiceName := "test_client"

			serverServiceName := "test_server"
			if c.secure {
				// This uses the explicitly passed service name rather than the task's family name.
				serverServiceName = "custom_test_server"
			}
			tfVars["server_service_name"] = serverServiceName

			image := cfg.ConsulImageURI(c.enterprise)
			t.Logf("using consul image = %s", image)
			tfVars["consul_image"] = image
			if c.enterprise {
				license := os.Getenv("CONSUL_LICENSE")
				require.True(t, license != "", "CONSUL_LICENSE not found but is required for enterprise tests")

				// Pass the license via environment variable to help ensure it is not logged.
				tfEnvVars["TF_VAR_consul_license"] = license
			}

			applyOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: initOptions.TerraformDir,
				Vars:         tfVars,
				NoColor:      true,
				EnvVars:      tfEnvVars,
			})

			t.Cleanup(func() {
				if cfg.NoCleanupOnFailure && t.Failed() {
					logger.Log(t, "skipping resource cleanup because -no-cleanup-on-failure=true")
				} else {
					terraform.Destroy(t, applyOptions)
				}
			})

			terraform.Apply(t, applyOptions)

			// Wait for consul server to be up.
			var consulServerTaskARN string
			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
				tasks, err := helpers.ListTasks(t, c.ecsClusterARN, cfg.Region, fmt.Sprintf("consul-server-%s", randomSuffix))

				r.Check(err)
				require.NotNil(r, tasks)
				require.Len(r, tasks.TaskARNs, 1)
				consulServerTaskARN = tasks.TaskARNs[0]
			})

			var controllerTaskID string
			if c.secure {
				retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
					tasks, err := helpers.ListTasks(t, c.ecsClusterARN, cfg.Region, fmt.Sprintf("%s-consul-ecs-controller", randomSuffix))

					r.Check(err)
					require.NotNil(r, tasks)
					require.Len(r, tasks.TaskARNs, 1)

					controllerTaskID = helpers.GetTaskIDFromARN(tasks.TaskARNs[0])
				})

				// Check controller logs to see if the anonymous token gets configured. This should
				// indicate that the controller has created the service auth method, policies and roles.
				retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
					appLogs, err := helpers.GetCloudWatchLogEvents(t, cfg, c.ecsClusterARN, controllerTaskID, "consul-ecs-controller")
					require.NoError(r, err)

					logMsg := "Successfully configured the anonymous token"
					appLogs = appLogs.Filter(logMsg)
					require.Len(r, appLogs, 1)
					require.Contains(r, appLogs[0].Message, logMsg)
				})
			}

			// Wait for both tasks to be registered in Consul.
			retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
				out, err := helpers.ExecuteRemoteCommand(t, cfg, c.ecsClusterARN, consulServerTaskARN, "consul-server", `/bin/sh -c "consul catalog services"`)
				r.Check(err)
				if !strings.Contains(out, fmt.Sprintf("%s_%s", serverServiceName, randomSuffix)) ||
					!strings.Contains(out, fmt.Sprintf("%s_%s", clientServiceName, randomSuffix)) {
					r.Errorf("services not yet registered, got %q", out)
				}
			})

			// Wait for passing health check for test_server and test_client
			tokenHeader := ""
			if c.secure {
				tokenHeader = `-H "X-Consul-Token: $CONSUL_HTTP_TOKEN"`
			}

			// Wait for passing health check for `serverServiceName` and `clientServiceName`.
			// `clientServiceName` has a check synced from ECS and a consul-dataplane check.
			// We check if both of them are in a passing state.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
				out, err := helpers.ExecuteRemoteCommand(
					t, cfg, c.ecsClusterARN, consulServerTaskARN, "consul-server",
					fmt.Sprintf(`/bin/sh -c 'curl %s localhost:8500/v1/health/checks/%s_%s'`, tokenHeader, clientServiceName, randomSuffix),
				)
				r.Check(err)

				statusRegex := regexp.MustCompile(`"Status"\s*:\s*"passing"`)
				if statusRegex.FindAllString(out, 2) == nil {
					r.Errorf("Check status not yet passing")
				}
			})

			// `serverServiceName` has a backing consul-dataplane check.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
				out, err := helpers.ExecuteRemoteCommand(
					t, cfg, c.ecsClusterARN, consulServerTaskARN, "consul-server",
					fmt.Sprintf(`/bin/sh -c 'curl %s localhost:8500/v1/health/checks/%s_%s'`, tokenHeader, serverServiceName, randomSuffix),
				)
				r.Check(err)

				statusRegex := regexp.MustCompile(`"Status"\s*:\s*"passing"`)
				if statusRegex.FindAllString(out, 1) == nil {
					r.Errorf("Check status not yet passing")
				}
			})

			// Use aws exec to curl between the apps.
			tasks, err := helpers.ListTasks(t, c.ecsClusterARN, cfg.Region, fmt.Sprintf("Test_Client_%s", randomSuffix))

			require.NoError(t, err)
			require.Len(t, tasks.TaskARNs, 1)

			testClientTaskARN := tasks.TaskARNs[0]
			testClientTaskID := helpers.GetTaskIDFromARN(tasks.TaskARNs[0])

			// Create an intention.
			if c.secure {
				// First check that connection between apps is unsuccessful.
				retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
					curlOut, err := helpers.ExecuteRemoteCommand(t, cfg, c.ecsClusterARN, testClientTaskARN, "basic", `/bin/sh -c "curl localhost:1234"`)
					r.Check(err)
					if !strings.Contains(curlOut, `curl: (52) Empty reply from server`) {
						r.Errorf("response was unexpected: %q", curlOut)
					}
				})
				retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
					consulCmd := fmt.Sprintf(`/bin/sh -c "consul intention create %s_%s %s_%s"`, clientServiceName, randomSuffix, serverServiceName, randomSuffix)
					_, err := helpers.ExecuteRemoteCommand(t, cfg, c.ecsClusterARN, consulServerTaskARN, "consul-server", consulCmd)
					r.Check(err)
				})
			}

			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
				curlOut, err := helpers.ExecuteRemoteCommand(t, cfg, c.ecsClusterARN, testClientTaskARN, "basic", `/bin/sh -c "curl localhost:1234"`)
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
			helpers.StopTask(t, c.ecsClusterARN, cfg.Region, testClientTaskARN, "Stopped to validate graceful shutdown in acceptance tests")

			// Wait for the task to stop (~30 seconds)
			retry.RunWith(&retry.Timer{Timeout: 1 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
				describeTasks, err := helpers.DescribeTasks(t, c.ecsClusterARN, cfg.Region, testClientTaskARN)

				r.Check(err)
				require.NotNil(r, describeTasks)
				require.Len(r, describeTasks.Tasks, 1)
				require.NotEqual(r, "RUNNING", describeTasks.Tasks[0].LastStatus)
			})

			// Check logs to see that the application ignored the TERM signal and exited about 10s later.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				appLogs, err := helpers.GetCloudWatchLogEvents(t, cfg, c.ecsClusterARN, testClientTaskID, "basic")
				require.NoError(r, err)

				logMsg := "consul-ecs: received sigterm. waiting 10s before terminating application."
				appLogs = appLogs.Filter(logMsg)
				require.Len(r, appLogs, 1)
				require.Contains(r, appLogs[0].Message, logMsg)
			})

			// Check that the Envoy entrypoint received the sigterm.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				envoyLogs, err := helpers.GetCloudWatchLogEvents(t, cfg, c.ecsClusterARN, testClientTaskID, "consul-dataplane")
				require.NoError(r, err)

				logMsg := "consul-ecs: waiting for application container(s) to stop"
				envoyLogs = envoyLogs.Filter(logMsg)
				require.GreaterOrEqual(r, len(envoyLogs), 1)
				require.Contains(r, envoyLogs[0].Message, logMsg)
			})

			// Retrieve "shutdown-monitor" logs to check outgoing requests succeeded.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				monitorLogs, err := helpers.GetCloudWatchLogEvents(t, cfg, c.ecsClusterARN, testClientTaskID, "shutdown-monitor")
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

			if c.secure {
				retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
					// Validate that the controller cleans up the token for the failed task
					syncLogs, err := helpers.GetCloudWatchLogEvents(t, cfg, c.ecsClusterARN, controllerTaskID, "consul-ecs-controller")
					require.NoError(r, err)
					syncLogs = syncLogs.Filter("token deleted successfully")
					require.GreaterOrEqual(r, len(syncLogs), 1)
				})
			}

			logger.Log(t, "Test successful!")
		})
	}
}
