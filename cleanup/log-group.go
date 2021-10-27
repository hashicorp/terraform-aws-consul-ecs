package main

import (
	"context"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/hashicorp/go-multierror"
)

type LogGroup struct {
	name string
}

func (l LogGroup) String() string {
	return l.name
}

func (l LogGroup) Delete() error {
	panic("implement me")
}

func (l LogGroup) Wait() error {
	panic("implement me")
}

func ListLogGroups(cfg aws.Config, ctx context.Context, resourceChan chan Resource) error {
	cwlClient := cloudwatchlogs.NewFromConfig(cfg)
	groups, err := cwlClient.DescribeLogGroups(ctx, &cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: aws.String("consul-ecs"),
	})
	if err != nil {
		return err
	}

	var errors error
	for _, group := range groups.LogGroups {
		groupTags, err := cwlClient.ListTagsLogGroup(ctx, &cloudwatchlogs.ListTagsLogGroupInput{
			LogGroupName: group.LogGroupName,
		})
		if err != nil {
			errors = multierror.Append(errors, err)
			continue
		}

		buildUrl := groupTags.Tags[buildUrlTagName]
		buildTime := groupTags.Tags[buildTimeTagName]
		if strings.Contains(buildUrl, buildUrlPrefix) && isOldBuildTime(buildTime) {
			resourceChan <- LogGroup{name: *group.LogGroupName}
		}
	}
	return errors
}
