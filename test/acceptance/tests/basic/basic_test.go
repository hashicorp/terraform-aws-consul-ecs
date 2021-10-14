package basic

import (
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/ecs"
	terratestLogger "github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	terratestTesting "github.com/gruntwork-io/terratest/modules/testing"
	"github.com/hashicorp/consul/sdk/testutil/retry"
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
	cases := []bool{false, true}

	for _, secure := range cases {
		t.Run(fmt.Sprintf("secure: %t", secure), func(t *testing.T) {
			randomSuffix := strings.ToLower(random.UniqueId())
			tfVars := suite.Config().TFVars()
			tfVars["secure"] = secure
			tfVars["suffix"] = randomSuffix
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
				out, err := executeRemoteCommand(t, consulServerTaskARN, "consul-server", `/bin/sh -c "consul catalog services"`)
				r.Check(err)
				if !strings.Contains(out, fmt.Sprintf("test_client_%s", randomSuffix)) ||
					!strings.Contains(out, fmt.Sprintf("test_server_%s", randomSuffix)) {
					r.Errorf("services not yet registered, got %q", out)
				}
			})

			// Wait for passing health check for test_server
			tokenHeader := ""
			if secure {
				tokenHeader = `-H "X-Consul-Token: $CONSUL_HTTP_TOKEN"`
			}
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
				out, err := shell.RunCommandAndGetOutputE(t, shell.Command{
					Command: "aws",
					Args: []string{
						"ecs",
						"execute-command",
						"--region",
						suite.Config().Region,
						"--cluster",
						suite.Config().ECSClusterARN,
						"--task",
						consulServerTaskARN,
						"--container=consul-server",
						"--command",
						fmt.Sprintf(`/bin/sh -c 'curl %s localhost:8500/v1/health/checks/test_server_%s'`, tokenHeader, randomSuffix),
						"--interactive",
					},
					Logger: terratestLogger.New(logger.TestLogger{}),
				})
				r.Check(err)

				statusRegex := regexp.MustCompile(`"Status"\s*:\s*"passing"`)
				if statusRegex.FindAllString(out, 1) == nil {
					r.Errorf("Check status not yet passing")
				}
			})

			// Find the TaskARN and TaskID for the client app
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

			// Create an intention.
			if secure {
				// First check that connection between apps is unsuccessful.
				retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
					curlOut, err := executeRemoteCommand(t, testClientTaskARN, "basic", `/bin/sh -c "curl localhost:1234"`)
					r.Check(err)
					if !strings.Contains(curlOut, `curl: (52) Empty reply from server`) {
						r.Errorf("response was unexpected: %q", curlOut)
					}
				})
				retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
					consulCmd := fmt.Sprintf(`/bin/sh -c "consul intention create test_client_%s test_server_%s"`, randomSuffix, randomSuffix)
					_, err := executeRemoteCommand(t, consulServerTaskARN, "consul-server", consulCmd)
					r.Check(err)
				})
			}

			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
				curlOut, err := executeRemoteCommand(t, testClientTaskARN, "basic", `/bin/sh -c "curl localhost:1234"`)
				r.Check(err)
				if !strings.Contains(curlOut, `"code": 200`) {
					r.Errorf("response was unexpected: %q", curlOut)
				}
			})

			// Check the client app can reach its upstream for about 10s after its task is stopped.
			//
			// For this test,
			// * the client app has a custom entrypoint to ignore the term signal, and
			// * mesh-init is responsible for ensuring Envoy ignores the term signal.
			//
			// Since this is timing dependent, we check logs after the fact to validate when containers exited.
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
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 15 * time.Second}, t, func(r *retry.R) {
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
				appLogs, err := getCloudWatchLogEvents(t, suite.Config().LogGroupName,
					fmt.Sprintf("test_client_%s/basic/%s", randomSuffix, testClientTaskID),
				)
				require.NoError(r, err)

				appLogs = appLogs.Filter("TEST LOG:")
				require.Len(r, appLogs, 2)
				require.Equal(r, appLogs[0].Message, "TEST LOG: Caught sigterm. Sleeping 10s...")
				require.Equal(r, appLogs[1].Message, "TEST LOG: on exit")
				require.InDelta(r, 10, appLogs.Duration().Seconds(), 1)
			})

			// Check that Envoy ignored the sigterm.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				envoyLogs, err := getCloudWatchLogEvents(t, suite.Config().LogGroupName,
					fmt.Sprintf("test_client_%s/sidecar-proxy/%s", randomSuffix, testClientTaskID),
				)
				require.NoError(r, err)
				envoyLogs = envoyLogs.Filter("Ignored sigterm")
				require.Len(r, envoyLogs, 1)
				require.Equal(r, envoyLogs[0].Message, "Ignored sigterm to support graceful task shutdown.")
			})

			// Retrieve "shutdown-monitor" logs to check outgoing requests succeeded.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				monitorLogs, err := getCloudWatchLogEvents(t, suite.Config().LogGroupName,
					fmt.Sprintf("test_client_%s/shutdown-monitor/%s", randomSuffix, testClientTaskID))
				require.NoError(r, err)

				// Check how long after shutdown the upstream was reachable.
				upstreamOkLogs := monitorLogs.Filter(
					"Signal received: signal=terminated",
					"upstream: [OK] GET http://localhost:1234",
				)
				// The client app is configured to run for about 10 seconds after Task shutdown.
				require.GreaterOrEqual(r, len(upstreamOkLogs.Filter("upstream: [OK]")), 7)
				require.GreaterOrEqual(r, upstreamOkLogs.Duration().Seconds(), 8.0)

				// Double-check the application was still functional for about 10 seconds into Task shutdown.
				// The FakeService makes requests to the upstream, so this further validates Envoy allows outgoing requests.
				applicationOkLogs := monitorLogs.Filter(
					"Signal received: signal=terminated",
					"application: [OK] GET http://localhost:9090",
				)
				require.GreaterOrEqual(r, len(applicationOkLogs.Filter("application: [OK]")), 7)
				require.GreaterOrEqual(r, applicationOkLogs.Duration().Seconds(), 8.0)
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
		})
	}
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}

// executeRemoteCommand executes a command inside a container in the task specified
// by taskARN.
func executeRemoteCommand(t *testing.T, taskARN, container, command string) (string, error) {
	return shell.RunCommandAndGetOutputE(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"execute-command",
			"--region",
			suite.Config().Region,
			"--cluster",
			suite.Config().ECSClusterARN,
			"--task",
			taskARN,
			fmt.Sprintf("--container=%s", container),
			"--command",
			command,
			"--interactive",
		},
		Logger: terratestLogger.New(logger.TestLogger{}),
	})
}

// getCloudWatchLogEvents fetch all log events for the given log stream.
func getCloudWatchLogEvents(t terratestTesting.TestingT, groupName, streamName string) (LogMessages, error) {
	getLogs := func(nextToken string) (listLogEventsResponse, error) {
		args := []string{
			"aws", "logs", "get-log-events",
			"--region", suite.Config().Region,
			"--log-group-name", groupName,
			"--log-stream-name", streamName,
		}
		if nextToken != "" {
			args = append(args, "--next-token", nextToken)
		}
		var resp listLogEventsResponse
		getLogEventsOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{Command: args[0], Args: args[1:]})
		if err != nil {
			return resp, err
		}

		err = json.Unmarshal([]byte(getLogEventsOut), &resp)
		return resp, err
	}

	resp, err := getLogs("")
	if err != nil {
		return nil, err
	}

	events := resp.Events
	forwardToken := resp.NextForwardToken
	backwardToken := resp.NextBackwardToken

	// Collect log events in the backwards direction
	for {
		resp, err = getLogs(backwardToken)
		if err != nil {
			return nil, err
		}
		events = append(resp.Events, events...)
		// "If you have reached the end of the stream, it returns the same token you passed in."
		if backwardToken == resp.NextBackwardToken {
			break
		}
		backwardToken = resp.NextBackwardToken
	}

	// Collect log events in the forwards direction
	for {
		resp, err = getLogs(forwardToken)
		if err != nil {
			return nil, err
		}
		events = append(events, resp.Events...)
		// "If you have reached the end of the stream, it returns the same token you passed in."
		if forwardToken == resp.NextForwardToken {
			break
		}
		forwardToken = resp.NextForwardToken
	}
	result := LogMessages(events)
	result.Sort()
	return result, nil
}

type logEvent struct {
	Timestamp int64  `json:"timestamp"`
	Message   string `json:"message"`
	Ingestion int64  `json:"ingestion"`
}

type listLogEventsResponse struct {
	Events            []logEvent `json:"events"`
	NextForwardToken  string     `json:"nextForwardToken"`
	NextBackwardToken string     `json:"nextBackwardToken"`
}

type LogMessages []logEvent

// Sort will sort these log events by timestamp.
func (lm LogMessages) Sort() {
	sort.Slice(lm, func(i, j int) bool { return lm[i].Timestamp < lm[j].Timestamp })
}

// Filter return those log events that contain any of the filterStrings.
func (lm LogMessages) Filter(filterStrings ...string) LogMessages {
	var result []logEvent
	for _, event := range lm {
		for _, filterStr := range filterStrings {
			if strings.Contains(event.Message, filterStr) {
				result = append(result, event)
			}
		}
	}
	return result
}

// Duration returns the difference between the max and min log timestamps.
// Returns a zero duration if there are zero or one log events.
func (lm LogMessages) Duration() time.Duration {
	if len(lm) < 2 {
		return 0
	}
	lm.Sort() // Ensure sorted by timestamp first
	last := lm[len(lm)-1]
	first := lm[0]
	// CloudWatch timestamps are in milliseconds
	return time.Duration(int64(time.Millisecond) * (last.Timestamp - first.Timestamp))
}
