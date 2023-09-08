package perf

import (
	"encoding/json"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/hashicorp/consul/api"
	"github.com/stretchr/testify/require"
)

const (
	pollInterval = time.Second * 30
	cluster      = "ecs-perf"
)

type serviceGroupsInfo struct {
	// Keeps track of the restarts applied to each service group
	// Restart happens when `PercentRestarts` percent of tasks in a
	// service group gets killed.
	restartsPerSvcGroup map[int]int

	healthyGroups map[int]struct{}
}

func newServiceGroupsInfo(serviceGroups int) *serviceGroupsInfo {
	restartsMap := make(map[int]int)
	for i := 0; i < serviceGroups; i++ {
		restartsMap[i] = 0
	}

	return &serviceGroupsInfo{
		restartsPerSvcGroup: restartsMap,
	}
}

func (s *serviceGroupsInfo) incrementRestart(svcGroup int) {
	s.restartsPerSvcGroup[svcGroup]++
}

func (s *serviceGroupsInfo) printRestartInfo() {
	fmt.Println("SvcGroup     Restart")
	for i, restartCount := range s.restartsPerSvcGroup {
		fmt.Printf("%d      %d\n", i, restartCount)
	}
}

func TestRun(t *testing.T) {
	config := testSuite.Config()
	fmt.Println("Running terraform apply to spin up test resources")

	config.terraformInit(t)
	config.terraformApply(t, true)

	t.Cleanup(func() {
		config.terraformApply(t, false)
	})

	outputVariables := terraformOutput(t)

	cfg := &api.Config{
		Address: outputVariables.ConsulELBURL,
		Token:   outputVariables.BootstrapToken,
	}
	consulClient, err := api.NewClient(cfg)
	require.NoError(t, err)

	realRun(t, consulClient, config)
}

func realRun(t *testing.T, consulClient *api.Client, config *TestConfig) {
	svcGroupsInfo := newServiceGroupsInfo(config.ServiceGroups)

	for {
		time.Sleep(pollInterval)
		svcGroupsInfo.printRestartInfo()

		svcGroupsInfo.healthyGroups = determineHealthyServiceGroups(t, consulClient, config)

		fmt.Printf("%d / %d service groups are healthy.\n", len(svcGroupsInfo.healthyGroups), config.ServiceGroups)

		svcGroupsToKill := determineServiceGroupsToKill(t, config, svcGroupsInfo)

		if isDone(svcGroupsInfo, config) {
			fmt.Println("Experiment complete!!!")
			break
		}

		for i := range svcGroupsToKill {
			killTasksInSvcGroup(t, i, config, svcGroupsInfo)
		}
	}
}

func determineHealthyServiceGroups(t *testing.T, consulClient *api.Client, config *TestConfig) map[int]struct{} {
	healthyServiceGroups := make(map[int]struct{})
	for i := 0; i < config.ServiceGroups; i++ {
		clientName := fmt.Sprintf("ecs-perf-%d-example-client-app", i)
		serverName := fmt.Sprintf("ecs-perf-%d-example-server-app", i)

		healthyClients := getHealthyInstancesForService(t, consulClient, clientName)
		healthyServers := getHealthyInstancesForService(t, consulClient, serverName)

		if healthyClients == config.ClientInstancesPerServiceGroup &&
			healthyServers == config.ServerInstancesPerServiceGroup {
			healthyServiceGroups[i] = struct{}{}
		}
	}

	return healthyServiceGroups
}

func determineServiceGroupsToKill(t *testing.T, config *TestConfig, svcGroupsInfo *serviceGroupsInfo) map[int]struct{} {
	toKill := make(map[int]struct{})
	for i := range svcGroupsInfo.healthyGroups {
		if svcGroupsInfo.restartsPerSvcGroup[i] >= config.Restarts {
			continue
		}

		toKill[i] = struct{}{}
	}

	return toKill
}

func getHealthyInstancesForService(t *testing.T, consulClient *api.Client, svc string) int {
	qopts := &api.QueryOptions{
		Namespace: "default",
		Partition: "default",
	}

	var services []*api.ServiceEntry
	var err error
	services, _, err = consulClient.Health().Service(svc, "", false, qopts)
	require.NoError(t, err)

	healthyInstances := 0
	for _, s := range services {
		healthy := true
		for _, c := range s.Checks {
			healthy := c.Status == api.HealthPassing
			if !healthy {
				break
			}
		}

		if healthy {
			healthyInstances++
		}
	}
	return healthyInstances
}

func isDone(svcGroupsInfo *serviceGroupsInfo, config *TestConfig) bool {
	if len(svcGroupsInfo.healthyGroups) < config.ServiceGroups {
		return false
	}

	done := true
	for i := range svcGroupsInfo.healthyGroups {
		if svcGroupsInfo.restartsPerSvcGroup[i] < config.Restarts {
			done = false
			break
		}
	}

	return done
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}

func killTasksInSvcGroup(t *testing.T, svcGroup int, config *TestConfig, svcGroupsInfo *serviceGroupsInfo) {
	fmt.Printf("Killing tasks in service group %d\n", svcGroup)
	family := fmt.Sprintf("ecs-perf-%d-example-server-app", svcGroup)

	taskListOut := shell.RunCommandAndGetOutput(t, shell.Command{
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
	taskARNS := tasks.TaskARNs[:len(tasks.TaskARNs)-2]

	var wg sync.WaitGroup
	for _, arn := range taskARNS {
		wg.Add(1)
		go func(arn string) {
			defer wg.Done()
			shell.RunCommand(t, shell.Command{
				Logger:  logger.Discard,
				Command: "aws",
				Args: []string{
					"ecs",
					"stop-task",
					"--region", "us-west-2",
					"--cluster", cluster,
					"--task", arn,
					"--reason", "Stopped to test ECS controller's performance",
				},
			})
		}(arn)
	}

	wg.Wait()

	svcGroupsInfo.incrementRestart(svcGroup)
	fmt.Printf("Stopped %d tasks successfully!!\n", len(taskARNS))
}
