package helpers

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"testing"

	"github.com/hashicorp/consul/api"
	"github.com/stretchr/testify/require"
)

// MeshTaskConfig holds the configuration for a Consul ECS MeshTask.
type MeshTaskConfig struct {
	ConsulClient *api.Client
	Name         string
	Partition    string
	Namespace    string
	Region       string
	ClusterARN   string
}

// MeshTask represents a Consul ECS mesh task and provides utility functions for interacting with it.
type MeshTask struct {
	MeshTaskConfig
	taskARN string
}

// NewMeshTask creates an instance of a MeshTask.
// It returns an error if any required configuration fields are missing.
func NewMeshTask(t *testing.T, cfg MeshTaskConfig) *MeshTask {
	require.NotNil(t, cfg.ConsulClient)
	require.NotEmpty(t, cfg.Name)
	require.NotEmpty(t, cfg.Partition)
	require.NotEmpty(t, cfg.Namespace)
	require.NotEmpty(t, cfg.Region)
	require.NotEmpty(t, cfg.ClusterARN)

	return &MeshTask{MeshTaskConfig: cfg}
}

// Registered indicates if the service for the task is registered in Consul.
func (task *MeshTask) Registered() bool {
	services, _, err := task.ConsulClient.Catalog().Services(task.QueryOpts())
	if err == nil {
		for name := range services {
			if name == task.Name {
				return true
			}
		}
	}
	return false
}

// Healthy indicates if all the service checks for the task are passing.
func (task *MeshTask) Healthy() bool {
	// list services by name filtered by ones with passing health checks
	services, _, err := task.ConsulClient.Health().Service(task.Name, "", true, task.QueryOpts())
	if err == nil && len(services) > 0 {
		return true
	}
	return false
}

// ExecuteCommand runs the command in the given container for the task.
func (task *MeshTask) ExecuteCommand(container, command string) (string, error) {
	taskARN, err := task.TaskARN()
	if err != nil {
		return "", fmt.Errorf("failed to get task ARN: %w", err)
	}
	args := []string{
		"ecs",
		"execute-command",
		"--interactive",
		"--region", task.Region,
		"--cluster", task.ClusterARN,
		"--task", taskARN,
		"--container", container,
		"--command", command,
	}
	cmd := exec.Command("aws", args...)
	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("failed to exec `aws %v`: %w", args, err)
	}
	return string(cmdOutput), nil
}

// TaskARN returns the ARN of the task instance for the service.
// If the ARN is already known it is returned, otherwise it is
// retrieved using the aws CLI using the properties of the service.
func (task *MeshTask) TaskARN() (string, error) {
	// if the task ARN is already known then return it.
	if task.taskARN != "" {
		return task.taskARN, nil
	}

	args := []string{
		"ecs",
		"list-tasks",
		"--region", task.Region,
		"--cluster", task.ClusterARN,
		"--family", task.Name,
	}
	cmd := exec.Command("aws", args...)
	taskListOut, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("failed to exec `aws %v`: %w", args, err)
	}

	type listTasksResponse struct {
		TaskARNs []string `json:"taskArns"`
	}
	var tasks listTasksResponse
	if err = json.Unmarshal([]byte(taskListOut), &tasks); err != nil {
		return "", fmt.Errorf("failed to unmarshal list-task response: %w", err)
	}
	if len(tasks.TaskARNs) < 1 {
		return "", fmt.Errorf("failed to find task ARN for %s", task.Name)
	}

	task.taskARN = tasks.TaskARNs[0]
	return task.taskARN, nil
}

// QueryOpts returns the Consul API query options for the task.
func (task *MeshTask) QueryOpts() *api.QueryOptions {
	return &api.QueryOptions{
		Partition: task.Partition,
		Namespace: task.Namespace,
	}
}

// WriteOpts returns the Consul API write options for the task.
func (task *MeshTask) WriteOpts() *api.WriteOptions {
	return &api.WriteOptions{
		Partition: task.Partition,
		Namespace: task.Namespace,
	}
}
