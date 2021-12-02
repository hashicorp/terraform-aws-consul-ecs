package perf

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/api"
	"github.com/montanaflynn/stats"
	"github.com/stretchr/testify/require"
)

const (
	cluster      = "consul-ecs-perf"
	pollInterval = 10 * time.Second
	maxDuration  = 30 * time.Minute
)

func TestRun(t *testing.T) {
	InitMetrics(t)
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

	strategy := NewEverythingStabilizes(config.ServiceGroups, config.Restarts)
	if config.Mode == "service-group" {
		strategy = NewServiceGroupStabilizes(config.ServiceGroups, config.Restarts)
	}

	ensureEverythingIsRunning(t, consulClient, strategy)
}

type ServiceGroupState map[int][]time.Time

func (sgs ServiceGroupState) done(restarts int) bool {
	for _, durations := range sgs {
		if len(durations) != restarts {
			return false
		}
	}
	return true
}

func ensureEverythingIsRunning(t *testing.T, consulClient *api.Client, strategy Strategy) {
	fmt.Println("Monitoring for healthy services")
	config := testSuite.Config()

	for {
		time.Sleep(pollInterval)

		fmt.Print("Pulling service groups. ")
		var currentlyHealthy []int
		for i := 0; i < config.ServiceGroups; i++ {
			clientName := fmt.Sprintf("consul-ecs-perf-%d-load-client", i)
			serverName := fmt.Sprintf("consul-ecs-perf-%d-test-server", i)

			clientRunning := getHealthyCount(t, consulClient, clientName) == 1
			serverRunning := getHealthyCount(t, consulClient, serverName) >= config.ServerInstancesPerServiceGroup
			if clientRunning && serverRunning {
				currentlyHealthy = append(currentlyHealthy, i)
			}
		}

		fmt.Printf("%d / %d are healthy.\n", len(currentlyHealthy), config.ServiceGroups)

		// TODO naming is hard. strategy.ServiceGroupsToDelete updates the internal
		// state for the strategy so it isn't the best name.
		toKill := strategy.ServiceGroupsToDelete(currentlyHealthy, time.Now())

		if strategy.Done() {
			fmt.Println("Every service has completed")
			summaryStatistics := getSummaryStatistics(t, strategy, *config)
			fmt.Printf("SummaryStatistics:\n%+v\n", summaryStatistics)
			return
		}

		for _, i := range toKill {
			killTasksForServiceGroup(t, i)
		}
	}
}

func getHealthyCount(t *testing.T, consulClient *api.Client, serviceName string) int {
	services, _, err := consulClient.Health().Service(serviceName, "", false, nil)
	require.NoError(t, err)

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

func killTasksForServiceGroup(t *testing.T, i int) {
	config := testSuite.Config()

	fmt.Printf("Killing tasks for service group %d\n", i)
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

type SummaryStatistics struct {
	Min               time.Duration
	Mean              time.Duration
	StandardDeviation time.Duration
	Median            time.Duration
	P90               time.Duration
	P95               time.Duration
	P99               time.Duration
	Max               time.Duration
}

func getSummaryStatistics(t *testing.T, s Strategy, config TestConfig) SummaryStatistics {
	timeseries := s.Data()

	var seconds []float64

	for _, event := range timeseries {
		seconds = append(seconds, float64(event.duration.Seconds()))
	}

	if config.OutputCSVPath != "" {
		f, err := os.Create(config.OutputCSVPath)
		require.NoError(t, err)
		f.WriteString("time,duration\n")
		defer f.Close()

		for _, event := range timeseries {
			f.WriteString(fmt.Sprintf("%s,%s\n", event.time.Format(time.RFC3339Nano), event.duration))
		}
	}

	mean, err := stats.Mean(seconds)
	require.NoError(t, err)

	min, err := stats.Min(seconds)
	require.NoError(t, err)

	median, err := stats.Median(seconds)
	require.NoError(t, err)

	max, err := stats.Max(seconds)
	require.NoError(t, err)

	p90, err := stats.Percentile(seconds, 90)
	require.NoError(t, err)

	p95, err := stats.Percentile(seconds, 95)
	require.NoError(t, err)

	p99, err := stats.Percentile(seconds, 99)
	require.NoError(t, err)

	standardDeviation, err := stats.StandardDeviation(seconds)
	require.NoError(t, err)

	toDuration := func(v float64) time.Duration {
		return time.Duration(int64(v)) * time.Second
	}

	return SummaryStatistics{
		Min:               toDuration(min),
		Mean:              toDuration(mean),
		Median:            toDuration(median),
		StandardDeviation: toDuration(standardDeviation),
		P90:               toDuration(p90),
		P95:               toDuration(p95),
		P99:               toDuration(p99),
		Max:               toDuration(max),
	}
}
