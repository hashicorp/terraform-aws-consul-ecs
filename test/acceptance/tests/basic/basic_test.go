package basic

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	terratestLogger "github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

// Test the validation that if dev_server_enabled=false then retry_join_url
// must be set.
func TestValidation_RetryJoinRequired(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/retry-join-validate",
		NoColor:      true,
	})
	defer terraform.Destroy(t, terraformOptions)
	_, err := terraform.InitAndPlanE(t, terraformOptions)
	require.Error(t, err)
	require.Contains(t, err.Error(), "ERROR: retry_join must be set if dev_server_enabled=false so that Consul clients can join the cluster")
}

func TestBasic(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/basic-install",
		Vars:         suite.Config().TFVars(),
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
				fmt.Sprintf("consul_server_%s", suite.Config().Suffix),
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
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
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
		if !strings.Contains(out, fmt.Sprintf("test_client_%s", suite.Config().Suffix)) ||
			!strings.Contains(out, fmt.Sprintf("test_server_%s", suite.Config().Suffix)) {
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
			fmt.Sprintf("test_client_%s", suite.Config().Suffix),
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
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}
