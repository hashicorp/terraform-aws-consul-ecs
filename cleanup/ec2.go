package main

import (
	"context"
	"fmt"
	"log"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2Types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
)

// EC2Instances implements the Resource interface
type EC2Instances struct {
	ids []string
	cfg aws.Config
}

func (e EC2Instances) String() string {
	return fmt.Sprint(e.ids)
}

func (e EC2Instances) Delete() error {
	log.Printf("Delete EC2 Instances: %v", e.ids)
	return nil
}

func (e EC2Instances) Wait() error {
	log.Printf("Wait for EC2 Instances: %v", e.ids)
	return nil
}

func ListEC2Instances(cfg aws.Config, ctx context.Context, resourceChan chan Resource) error {
	log.Println("Listing EC2 instances")
	ec2Client := ec2.NewFromConfig(cfg)
	instances, err := ec2Client.DescribeInstances(ctx, &ec2.DescribeInstancesInput{
		Filters: []ec2Types.Filter{
			{
				Name:   aws.String(fmt.Sprintf("tag:%s", buildUrlTagName)),
				Values: []string{buildUrlPrefixPlusStar},
			},
			{
				Name:   aws.String("tag:Name"),
				Values: []string{"consul-ecs-*"},
			},
			{
				Name:   aws.String("instance-state-name"),
				Values: []string{"running"},
			},
		},
	})
	if err != nil {
		return err
	}

	var ids []string
	for _, rsv := range instances.Reservations {
		for _, inst := range rsv.Instances {
			if isOldBuildTime(getTag(buildTimeTagName, inst.Tags)) {
				ids = append(ids, *inst.InstanceId)
			}
		}
	}
	if len(ids) > 0 {
		resourceChan <- EC2Instances{
			ids: ids,
			cfg: cfg,
		}
	}
	return nil
}
