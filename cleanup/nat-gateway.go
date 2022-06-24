package main

import (
	"context"
	"fmt"
	"log"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2Types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
)

type NatGateway struct {
	id string
}

func (n NatGateway) String() string {
	return n.id
}

func (n NatGateway) Delete() error {
	panic("implement me")
}

func (n NatGateway) Wait() error {
	panic("implement me")
}

func ListNatGateways(cfg aws.Config, ctx context.Context, resourceChan chan Resource) error {
	log.Println("Listing NAT gateways")
	ec2Client := ec2.NewFromConfig(cfg)
	gateways, err := ec2Client.DescribeNatGateways(ctx, &ec2.DescribeNatGatewaysInput{
		Filter: []ec2Types.Filter{
			{
				Name:   aws.String(fmt.Sprintf("tag:%s", buildUrlTagName)),
				Values: []string{buildUrlPrefixPlusStar},
			},
			{
				Name:   aws.String("tag:Name"),
				Values: []string{"consul-ecs-*"},
			},
			{
				Name: aws.String("state"),
				Values: []string{
					string(ec2Types.NatGatewayStateAvailable),
					string(ec2Types.NatGatewayStateFailed),
					string(ec2Types.NatGatewayStatePending),
				},
			},
		},
	})
	if err != nil {
		return err
	}

	for _, gw := range gateways.NatGateways {
		if isOldBuildTime(getTag(buildTimeTagName, gw.Tags)) {
			resourceChan <- NatGateway{*gw.NatGatewayId}
		}
	}
	return nil
}
