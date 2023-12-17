// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package common

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
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

// func (e *ECSClientWrapper) ExecuteCommandInteractive(taskARN, container, command string) {
// 	req := &ecs.ExecuteCommandInput{
// 		Container:   &container,
// 		Task:        &taskARN,
// 		Cluster:     &e.clusterARN,
// 		Command:     &command,
// 		Interactive: true,
// 	}
// 	res, err := e.client.ExecuteCommand(context.TODO(), req)
// 	res.ResultMetadata.Get()
// }
