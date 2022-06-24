package main

import (
	"context"
	"fmt"
	"log"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2Types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
)

type ElasticIP struct {
	allocationId string
}

func (e ElasticIP) String() string {
	return e.allocationId
}

func (e ElasticIP) Delete() error {
	panic("implement me")
}

func (e ElasticIP) Wait() error {
	panic("implement me")
}

func ListElasticIPs(cfg aws.Config, ctx context.Context, resourceChan chan Resource) error {
	log.Println("Listing elastic ips")
	ec2Client := ec2.NewFromConfig(cfg)
	addresses, err := ec2Client.DescribeAddresses(ctx, &ec2.DescribeAddressesInput{
		Filters: []ec2Types.Filter{
			{
				Name:   aws.String(fmt.Sprintf("tag:%s", buildUrlTagName)),
				Values: []string{buildUrlPrefixPlusStar},
			},
			{
				Name:   aws.String("tag:Name"),
				Values: []string{"consul-ecs-*"},
			},
		},
	})
	if err != nil {
		return err
	}

	// NOTE: May be associated (to the NAT gateway). If the NAT GW is deleted first,
	// it's okay, and we ensure that ordering elsewhere.
	for _, addr := range addresses.Addresses {
		if isOldBuildTime(getTag(buildTimeTagName, addr.Tags)) {
			resourceChan <- ElasticIP{allocationId: *addr.AllocationId}
		}
	}
	return nil
}
