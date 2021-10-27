package main

import (
	"context"
	"log"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
)

const (
	// AWS supports patterns for filtering on tags, but not on all APIs.
	buildUrlTagName = "build_url"
	// buildUrlPrefix = "https://circleci.com/gh/hashicorp/terraform-aws-consul-ecs/"
	buildUrlPrefix         = "http://test.example"
	buildUrlPrefixPlusStar = buildUrlPrefix + "*"

	// Only cleanup resources at least this old.
	// We rely on a tag for this since not all resources have a creation time.
	buildTimeTagName = "build_time"
	// resourceAge = 4 * 24 * time.Hour
	resourceAge = 30 * time.Second
)

type Resource interface {
	String() string
	Delete() error
	Wait() error
}

type ResourceListFn func(aws.Config, context.Context, chan Resource) error

func main() {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion("us-west-2"))
	if err != nil {
		log.Fatal(err)
	}

	resources := ListResources(cfg)
	for _, r := range resources {
		log.Printf("%T %v", r, r)
	}
}

func ListResources(cfg aws.Config) []Resource {
	ctx := context.Background()
	resourceChan := make(chan Resource, 10000)
	var wg sync.WaitGroup
	defer wg.Wait()

	listFns := []ResourceListFn{
		ListEC2Instances,
		ListECSClusters,
		ListNatGateways,
		ListVPCs,
		ListLogGroups,
		ListElasticIPs,
		// Expensive. No way to filter by name. And hits rate limits.
		// ListIamRoles,
	}
	for _, fn := range listFns {
		wg.Add(1)
		go func(lister ResourceListFn) {
			defer wg.Done()
			if err := lister(cfg, ctx, resourceChan); err != nil {
				log.Printf("error: %s", err)
			}
		}(fn)
	}

	wg.Wait()
	close(resourceChan) // so we can iterate over it

	var resources []Resource
	for r := range resourceChan {
		resources = append(resources, r)
	}
	return resources
}
