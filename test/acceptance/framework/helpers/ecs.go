package helpers

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/ecs"
	terratestLogger "github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

// ExecuteRemoteCommand executes a command inside a container in the task specified by the taskARN.
func ExecuteRemoteCommand(t *testing.T, testConfig *config.TestConfig, taskARN, container, command string) (string, error) {
	return shell.RunCommandAndGetOutputE(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"execute-command",
			"--region", testConfig.Region,
			"--cluster", testConfig.ECSClusterARN,
			"--task", taskARN,
			fmt.Sprintf("--container=%s", container),
			"--command", command,
			"--interactive",
		},
		Logger: terratestLogger.New(logger.TestLogger{}),
	})
}

// WaitForRemoteCommand runs the remote command until it returns the given output.
func WaitForRemoteCommand(t *testing.T, testConfig *config.TestConfig,
	taskArn, container, command, output string,
) {
	t.Logf("waiting for remote command `%s` to have output `%s`", command, output)
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		curlOut, err := ExecuteRemoteCommand(t, testConfig, taskArn, container, command)
		r.Check(err)
		if !strings.Contains(curlOut, output) {
			r.Errorf("response was unexpected: %q", curlOut)
		}
	})
}

// ListECSTasks lists tasks for a task family.
func ListECSTasks(t *testing.T, testConfig *config.TestConfig, family string) ecs.ListTasksOutput {
	taskListOut := shell.RunCommandAndGetOutput(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"list-tasks",
			"--region", testConfig.Region,
			"--cluster", testConfig.ECSClusterARN,
			"--family", family,
		},
	})

	var tasks ecs.ListTasksOutput
	require.NoError(t, json.Unmarshal([]byte(taskListOut), &tasks))
	return tasks
}

// StopECSTask stops the ECS task.
func StopECSTask(t *testing.T, testConfig *config.TestConfig, taskArn string) {
	t.Logf("Stopping, task=%s", taskArn)
	shell.RunCommandAndGetOutput(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"stop-task",
			"--region", testConfig.Region,
			"--cluster", testConfig.ECSClusterARN,
			"--task", taskArn,
			"--reason", "Stopped by acceptance tests",
		},
	})
}

// WaitForECSTask waits until the task's LastStatus matches the given status.
func WaitForECSTask(t *testing.T, testConfig *config.TestConfig, status, taskArn string) {
	t.Logf("Waiting for task status %s, task=%s", status, taskArn)
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		describeTasksOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
			Command: "aws",
			Args: []string{
				"ecs",
				"describe-tasks",
				"--region", testConfig.Region,
				"--cluster", testConfig.ECSClusterARN,
				"--task", taskArn,
			},
		})
		r.Check(err)

		var describeTasks ecs.DescribeTasksOutput
		r.Check(json.Unmarshal([]byte(describeTasksOut), &describeTasks))
		require.Len(r, describeTasks.Tasks, 1)
		require.Equal(r, status, *describeTasks.Tasks[0].LastStatus)
	})
}
