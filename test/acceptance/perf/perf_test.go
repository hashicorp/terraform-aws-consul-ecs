package perf

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/stretchr/testify/require"
)

const (
	cluster   = "consul-ecs-perf"
	sleepTime = 30 * time.Second
)

func TestRun(t *testing.T) {
	config := testSuite.Config()
	tfVars := config.TFVars()
	options := &terraform.Options{
		TerraformDir: "./setup",
		NoColor:      true,
		Vars:         tfVars,
	}

	terraformOptions := terraform.WithDefaultRetryableErrors(t, options)

	if !config.NoCleanup {
		t.Cleanup(func() {
			_, _ = terraform.DestroyE(t, terraformOptions)
		})
	}

	_, err := terraform.InitAndApplyE(t, terraformOptions)
	require.NoError(t, err)

	consulURL := terraform.Output(t, options, "consul_elb_url")
	bootstrapToken := terraform.Output(t, options, "bootstrap_token")

	consulClient, err := api.NewClient(&api.Config{Address: consulURL, Token: bootstrapToken})
	require.NoError(t, err)

	ensureEverythingIsRunning(t, consulClient)

	t.Log("Number of restarts", config.Restarts)
	for restart := 0; restart < config.Restarts; restart++ {
		t.Logf("Killing tasks attempt %d", restart+1)
		killTasks(t)
		ensureEverythingIsRunning(t, consulClient)
	}
}

func ensureEverythingIsRunning(t *testing.T, consulClient *api.Client) {
	// Wait long enough for some services to become unhealthy.
	time.Sleep(sleepTime)
	config := testSuite.Config()

	startTime := time.Now()

	t.Log("ensuring everything is running")

	retry.RunWith(&retry.Timer{Timeout: 7 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		unhealthy := make(map[int]struct{})
		for i := 0; i < config.ServiceGroups; i++ {
			clientName := fmt.Sprintf("consul-ecs-perf-%d-load-client", i)
			serverName := fmt.Sprintf("consul-ecs-perf-%d-test-server", i)

			if getHealthyCount(r, consulClient, clientName) != 1 || getHealthyCount(r, consulClient, serverName) != config.ServerInstancesPerServiceGroup {
				unhealthy[i] = struct{}{}
				continue
			}
		}

		t.Logf("%d / %d service groups are unhealthy\n", len(unhealthy), config.ServiceGroups)
		require.Equal(r, 0, len(unhealthy))
	})

	t.Logf("it took %s for the cluster to stabilize\n", time.Since(startTime)+sleepTime)
}

func getHealthyCount(r *retry.R, consulClient *api.Client, serviceName string) int {
	services, _, err := consulClient.Health().Service(serviceName, "", false, nil)
	r.Check(err)

	healthyCount := 0
	for _, service := range services {
		healthy := true
		for _, check := range service.Checks {
			healthy = api.HealthPassing == check.Status
			if !healthy {
				break
			}
		}
		if healthy {
			healthyCount++
		}
	}
	return healthyCount
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}

func killTasks(t *testing.T) {
	config := testSuite.Config()
	t.Log("Killing tasks")
	for i := 0; i < config.ServiceGroups; i++ {
		family := fmt.Sprintf("consul-ecs-perf-%d-test-server", i)

		taskListOut := shell.RunCommandAndGetOutput(t, shell.Command{
			Logger:  logger.Discard,
			Command: "aws",
			Args: []string{
				"ecs",
				"list-tasks",
				"--region",
				"us-west-2",
				"--cluster",
				cluster,
				"--family",
				family,
			},
		})

		var tasks listTasksResponse
		err := json.Unmarshal([]byte(taskListOut), &tasks)
		require.NoError(t, err)
		taskARNS := tasks.TaskARNs

		// Restart tasks for one service group at a time.
		tasksToKillPerService := config.ServerInstancesPerServiceGroup * config.PercentRestart / 100
		guard := make(chan struct{}, tasksToKillPerService)

		for i, taskARN := range taskARNS {
			if i >= tasksToKillPerService {
				break
			}
			guard <- struct{}{}
			go func(arn string) {
				shell.RunCommand(t, shell.Command{
					Logger:  logger.Discard,
					Command: "aws",
					Args: []string{
						"ecs",
						"stop-task",
						"--region", "us-west-2",
						"--cluster", cluster,
						"--task", arn,
						"--reason", "Stopped to test performance",
					},
				})
				<-guard
			}(taskARN)
		}
	}
}
