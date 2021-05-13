package flags

import (
	"flag"
	"sync"

	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
)

const (
	flagNoCleanupOnFailure = "no-cleanup-on-failure"
	flagClusterARN         = "cluster-arn"
	flagSubnets            = "subnets"
	flagSuffix             = "suffix"
	flagRegion             = "region"
	flagLogGroupName       = "log-group-name"
	// flagTFTags is named to disambiguate from the --tags flags used
	// by go test to specify build tags.
	flagTFTags = "tf-tags"
)

type TestFlags struct {
	flagNoCleanupOnFailure bool
	flagClusterARN         string
	flagSubnets            string
	flagSuffix             string
	flagRegion             string
	flagLogGroupName       string
	flagTFTags             string

	once sync.Once
}

func NewTestFlags() *TestFlags {
	t := &TestFlags{}
	t.once.Do(t.init)

	return t
}

func (t *TestFlags) init() {
	flag.BoolVar(&t.flagNoCleanupOnFailure, flagNoCleanupOnFailure, false,
		"If true, the tests will not clean up resources they create when they finish running."+
			"Note this flag must be run with -failfast flag, otherwise subsequent tests will fail.")
	flag.StringVar(&t.flagClusterARN, flagClusterARN, "", "ECS Cluster ARN.")
	flag.StringVar(&t.flagSubnets, flagSubnets, "", "Subnets to deploy into. In TF var form, e.g. '[\"sub1\",\"sub2\"]'.")
	flag.StringVar(&t.flagSuffix, flagSuffix, "", "Resource suffix.")
	flag.StringVar(&t.flagRegion, flagRegion, "", "Region.")
	flag.StringVar(&t.flagLogGroupName, flagLogGroupName, "", "CloudWatch log group name.")
	flag.StringVar(&t.flagTFTags, flagTFTags, "", "Tags to add to resources. In TF var form, e.g. '{key=val,key2=val2}'.")
}

func (t *TestFlags) Validate() error {
	// todo: require certain vars
	return nil
}

func (t *TestFlags) TestConfigFromFlags() *config.TestConfig {
	return &config.TestConfig{
		NoCleanupOnFailure: t.flagNoCleanupOnFailure,
		ClusterARN:         t.flagClusterARN,
		Subnets:            t.flagSubnets,
		Suffix:             t.flagSuffix,
		Region:             t.flagRegion,
		LogGroupName:       t.flagLogGroupName,
		Tags:               t.flagTFTags,
	}
}
