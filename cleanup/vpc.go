package main

import (
	"context"
	"fmt"
	"log"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2Types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
)

type VPC struct {
	id               string
	igwId            string
	subnetIds        []string
	securityGroupIds []string
	routeTableIds    []string
}

func (v VPC) String() string {
	return fmt.Sprintf("vpc=%s igw=%s subnets=%s secgroups=%s routetables=%s",
		v.id, v.igwId, v.subnetIds, v.securityGroupIds, v.routeTableIds)
}

func (v VPC) Delete() error {
	panic("implement me")
}

func (v VPC) Wait() error {
	panic("implement me")
}

func ListVPCs(cfg aws.Config, ctx context.Context, resourceChan chan Resource) error {
	log.Println("Listing VPCs")
	ec2Client := ec2.NewFromConfig(cfg)
	describeVpcs, err := ec2Client.DescribeVpcs(ctx, &ec2.DescribeVpcsInput{
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

	for _, vpc := range describeVpcs.Vpcs {
		if isOldBuildTime(getTag(buildTimeTagName, vpc.Tags)) {
			resourceChan <- VPC{
				id:               *vpc.VpcId,
				igwId:            getIgw(ec2Client, ctx, *vpc.VpcId),
				subnetIds:        listSubnets(ec2Client, ctx, *vpc.VpcId),
				securityGroupIds: listSecurityGroups(ec2Client, ctx, *vpc.VpcId),
				routeTableIds:    listRouteTables(ec2Client, ctx, *vpc.VpcId),
			}
		}
	}
	return nil
}

func getIgw(ec2Client *ec2.Client, ctx context.Context, vpcId string) string {
	log.Printf("Listing internet gateways in VPC %s", vpcId)
	gateways, err := ec2Client.DescribeInternetGateways(ctx, &ec2.DescribeInternetGatewaysInput{
		Filters: []ec2Types.Filter{
			{
				Name:   aws.String("attachment.vpc-id"),
				Values: []string{vpcId},
			},
		},
	})
	if err != nil {
		log.Printf("warning: error listing internet gateways: %s", err)
		return ""
	}

	if len(gateways.InternetGateways) >= 1 {
		return *gateways.InternetGateways[0].InternetGatewayId
	}
	return ""
}

func listSubnets(ec2Client *ec2.Client, ctx context.Context, vpcId string) []string {
	log.Printf("Listing subnets for VPC %s", vpcId)
	subnets, err := ec2Client.DescribeSubnets(ctx, &ec2.DescribeSubnetsInput{
		Filters: []ec2Types.Filter{
			{
				Name:   aws.String("vpc-id"),
				Values: []string{vpcId},
			},
		},
	})
	if err != nil {
		log.Printf("warning: error listing subnets: %s", err)
		return nil
	}

	var subnetIds []string
	for _, subnet := range subnets.Subnets {
		subnetIds = append(subnetIds, *subnet.SubnetId)
	}
	return subnetIds
}

func listSecurityGroups(ec2Client *ec2.Client, ctx context.Context, vpcId string) []string {
	log.Printf("Listing security groups for VPC %s", vpcId)
	groups, err := ec2Client.DescribeSecurityGroups(ctx, &ec2.DescribeSecurityGroupsInput{
		Filters: []ec2Types.Filter{
			{
				Name:   aws.String("vpc-id"),
				Values: []string{vpcId},
			},
		},
	})
	if err != nil {
		log.Printf("warning: error listing security groups: %s", err)
		return nil
	}

	var groupIds []string
	for _, group := range groups.SecurityGroups {
		groupIds = append(groupIds, *group.GroupId)
	}
	return groupIds
}

func listRouteTables(ec2Client *ec2.Client, ctx context.Context, vpcId string) []string {
	log.Printf("Listing route tables for VPC %s", vpcId)
	tables, err := ec2Client.DescribeRouteTables(ctx, &ec2.DescribeRouteTablesInput{
		Filters: []ec2Types.Filter{
			{
				Name:   aws.String("vpc-id"),
				Values: []string{vpcId},
			},
		},
	})
	if err != nil {
		log.Printf("warning: error listing security groups: %s", err)
		return nil
	}

	var routeTableIds []string
	for _, table := range tables.RouteTables {
		// Avoid deleting the main route table association.
		isMain := false
		for _, assoc := range table.Associations {
			if assoc.Main != nil && *assoc.Main {
				isMain = true
			}
		}
		if !isMain {
			routeTableIds = append(routeTableIds, *table.RouteTableId)
		}
	}
	return routeTableIds
}
