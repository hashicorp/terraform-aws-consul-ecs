// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package common

import (
	"context"
	"fmt"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/gruntwork-io/terratest/modules/shell"
)

type ECSClientWrapper struct {
	client     *ecs.Client
	clusterARN string
}

func NewECSClient() (*ECSClientWrapper, error) {
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		return nil, err
	}

	return &ECSClientWrapper{
		client: ecs.NewFromConfig(cfg),
	}, nil
}

func (e *ECSClientWrapper) WithClusterARN(clusterARN string) *ECSClientWrapper {
	e.clusterARN = clusterARN
	return e
}

// ListTasksForService returns back the taskARN list for a given service
func (e *ECSClientWrapper) ListTasksForService(service string) ([]string, error) {
	taskARNs := make([]string, 0)
	var nextToken *string
	for {
		req := &ecs.ListTasksInput{
			Cluster:     &e.clusterARN,
			ServiceName: &service,
			NextToken:   nextToken,
		}

		res, err := e.client.ListTasks(context.TODO(), req)
		if err != nil {
			return nil, err
		}
		nextToken = res.NextToken

		taskARNs = append(taskARNs, res.TaskArns...)
		if nextToken == nil {
			break
		}
	}

	return taskARNs, nil
}

// DescribeTasks returns back a detailed description of all the tasks passed as input.
func (e *ECSClientWrapper) DescribeTasks(taskIDs []string) (*ecs.DescribeTasksOutput, error) {
	req := &ecs.DescribeTasksInput{
		Tasks:   taskIDs,
		Cluster: &e.clusterARN,
	}

	return e.client.DescribeTasks(context.TODO(), req)
}

// StopTask stops a given task with a reason
func (e *ECSClientWrapper) StopTask(taskID, reason string) error {
	req := &ecs.StopTaskInput{
		Task:    &taskID,
		Cluster: &e.clusterARN,
		Reason:  &reason,
	}

	_, err := e.client.StopTask(context.TODO(), req)
	return err
}

func (e *ECSClientWrapper) UpdateService(serviceName string, desiredCount int32) error {
	req := &ecs.UpdateServiceInput{
		Service:      &serviceName,
		Cluster:      &e.clusterARN,
		DesiredCount: &desiredCount,
	}

	_, err := e.client.UpdateService(context.TODO(), req)
	return err
}

// ExecuteCommandInteractive runs the provided command inside a container in the ECS task
// and returns back the results.
//
// Note: Ideally we should try to use the SDK for this but it wasn't straight forward and
// there was no clear documentation around the same.
func (e *ECSClientWrapper) ExecuteCommandInteractive(t *testing.T, taskARN, container, command string) (string, error) {
	return shell.RunCommandAndGetOutputE(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"execute-command",
			"--cluster",
			e.clusterARN,
			"--task",
			taskARN,
			fmt.Sprintf("--container=%s", container),
			"--command",
			command,
			"--interactive",
		},
	})
}
