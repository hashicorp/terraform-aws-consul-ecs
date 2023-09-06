// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package helpers

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/gruntwork-io/terratest/modules/shell"
)

type ListTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}

func ListTasks(t *testing.T, clusterARN, region, family string) (*ListTasksResponse, error) {
	args := []string{
		"ecs",
		"list-tasks",
		"--region", region,
		"--cluster", clusterARN,
		"--family", family,
	}

	taskListOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
		Command: "aws",
		Args:    args,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to run `aws %v`: %w", args, err)
	}

	var tasks *ListTasksResponse
	err = json.Unmarshal([]byte(taskListOut), &tasks)
	if err != nil {
		return nil, err
	}

	return tasks, nil
}

func DescribeTasks(t *testing.T, clusterARN, region, taskARN string) (*ecs.DescribeTasksOutput, error) {
	args := []string{
		"ecs",
		"describe-tasks",
		"--region", region,
		"--cluster", clusterARN,
		"--task", taskARN,
	}

	taskListOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
		Command: "aws",
		Args:    args,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to run `aws %v`: %w", args, err)
	}

	var tasks *ecs.DescribeTasksOutput
	err = json.Unmarshal([]byte(taskListOut), &tasks)
	if err != nil {
		return nil, err
	}

	return tasks, nil
}

func StopTask(t *testing.T, clusterARN, region, taskARN, reason string) string {
	args := []string{
		"ecs",
		"stop-task",
		"--region", region,
		"--cluster", clusterARN,
		"--task", taskARN,
		"--reason", reason,
	}

	return shell.RunCommandAndGetOutput(t, shell.Command{
		Command: "aws",
		Args:    args,
	})
}

func GetTaskIDFromARN(taskARN string) string {
	arnParts := strings.Split(taskARN, "/")
	return arnParts[len(arnParts)-1]
}
