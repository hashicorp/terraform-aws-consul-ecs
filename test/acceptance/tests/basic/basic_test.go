package basic

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
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

// Test the validation that if either consul_server_service_name or retry_join_url
// must be set.
func TestValidation_RetryJoinRequired(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/retry-join-validate",
		NoColor:      true,
	})
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	_, err := terraform.InitAndPlanE(t, terraformOptions)
	require.Error(t, err)
	require.Contains(t, err.Error(), "ERROR: either consul_server_service_name or retry_join must be set so that Consul clients can join the cluster")
}

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

			defer func() {
				if suite.Config().NoCleanupOnFailure {
					logger.Log(t, "skipping resource cleanup because -no-cleanup-on-failure=true")
				} else {
					terraform.Destroy(t, terraformOptions)
				}
			}()
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
						`/bin/sh -c "consul catalog services"`,
						"--interactive",
					},
					Logger: terratestLogger.New(logger.TestLogger{}),
				})
				r.Check(err)
				if !strings.Contains(out, fmt.Sprintf("test_client_%s", randomSuffix)) ||
					!strings.Contains(out, fmt.Sprintf("test_server_%s", randomSuffix)) {
					r.Errorf("services not yet registered, got %q", out)
				}
			})

			// use aws exec to curl between the apps
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

			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
				curlOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
					Command: "aws",
					Args: []string{
						"ecs",
						"execute-command",
						"--region",
						suite.Config().Region,
						"--cluster",
						suite.Config().ECSClusterARN,
						"--task",
						tasks.TaskARNs[0],
						"--container=basic",
						"--command",
						`/bin/sh -c "curl localhost:1234"`,
						"--interactive",
					},
					Logger: terratestLogger.New(logger.TestLogger{}),
				})
				r.Check(err)
				if !strings.Contains(curlOut, `"code": 200`) {
					r.Errorf("response was unexpected: %q", curlOut)
				}
			})

			logger.Log(t, "Test successful!")
		})
	}
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}
