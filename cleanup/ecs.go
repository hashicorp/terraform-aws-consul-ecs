package main

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	ecsTypes "github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/hashicorp/go-multierror"
)

type ECSCluster struct {
	arn      string
	services []string
	cfg      aws.Config
}

func (e ECSCluster) String() string {
	return fmt.Sprintf("arn=%s services=%v", e.arn, e.services)
}

func (e ECSCluster) Delete() error {
	panic("implement me")
}

func (e ECSCluster) Wait() error {
	panic("implement me")
}

func ListECSClusters(cfg aws.Config, ctx context.Context, resourceChan chan Resource) error {
	log.Println("Listing ECS clusters")
	ecsClient := ecs.NewFromConfig(cfg)
	list, err := ecsClient.ListClusters(ctx, nil)
	if err != nil {
		return err
	}

	var allConsulEcsArns []string
	for _, arn := range list.ClusterArns {
		if strings.Contains(arn, "consul-ecs") {
			allConsulEcsArns = append(allConsulEcsArns, arn)
		}
	}

	describe, err := ecsClient.DescribeClusters(ctx, &ecs.DescribeClustersInput{
		Clusters: allConsulEcsArns,
		Include:  []ecsTypes.ClusterField{ecsTypes.ClusterFieldTags},
	})
	if err != nil {
		return err
	}

	var clustersToCleanup []*ECSCluster
	for _, cluster := range describe.Clusters {
		if *cluster.Status == "INACTIVE" {
			continue
		}
		buildUrl := getTag(buildUrlTagName, cluster.Tags)
		buildTimestamp := getTag(buildTimeTagName, cluster.Tags)
		if strings.Contains(buildUrl, buildUrlPrefix) && isOldBuildTime(buildTimestamp) {
			clustersToCleanup = append(clustersToCleanup, &ECSCluster{arn: *cluster.ClusterArn})
		}
	}

	// Services in the cluster must be deleted before the cluster can be deleted.
	var errors error
	for _, c := range clustersToCleanup {
		log.Printf("Listing ECS services for cluster=%s", c.arn)
		services, err := ecsClient.ListServices(ctx, &ecs.ListServicesInput{
			Cluster: aws.String(c.arn),
		})
		if err != nil {
			errors = multierror.Append(errors, err)
		} else {
			c.services = services.ServiceArns
		}
	}

	for _, c := range clustersToCleanup {
		resourceChan <- *c
	}
	return errors
}
