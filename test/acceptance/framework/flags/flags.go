package flags

import (
	"encoding/json"
	"flag"
	"fmt"
	"os/exec"
	"sync"

	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
)

const (
	flagNoCleanupOnFailure = "no-cleanup-on-failure"
	flagECSClusterARN      = "ecs-cluster-arn"
	flagSubnets            = "subnets"
	flagRegion             = "region"
	flagLogGroupName       = "log-group-name"
	// flagTFTags is named to disambiguate from the --tags flags used
	// by go test to specify build tags.
	flagTFTags      = "tf-tags"
	flagTFOutputDir = "tf-output-dir"

	setupTerraformDir = "../../setup-terraform"
)

type TestFlags struct {
	flagNoCleanupOnFailure bool
	flagECSClusterARN      string
	flagSubnets            string
	flagRegion             string
	flagLogGroupName       string
	flagTFTags             string
	flagTFOutputDir        string

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
	flag.StringVar(&t.flagECSClusterARN, flagECSClusterARN, "", "ECS Cluster ARN.")
	flag.StringVar(&t.flagSubnets, flagSubnets, "", "Subnets to deploy into. In TF var form, e.g. '[\"sub1\",\"sub2\"]'.")
	flag.StringVar(&t.flagRegion, flagRegion, "", "Region.")
	flag.StringVar(&t.flagLogGroupName, flagLogGroupName, "", "CloudWatch log group name.")
	flag.StringVar(&t.flagTFTags, flagTFTags, "", "Tags to add to resources. In TF var form, e.g. '{key=val,key2=val2}'.")
	flag.StringVar(&t.flagTFOutputDir, flagTFOutputDir, setupTerraformDir, "The directory of the setup terraform state for the tests.")
}

func (t *TestFlags) Validate() error {
	// todo: require certain vars
	return nil
}

type tfOutputItem struct {
	Value interface{}
	Type  interface{}
}

func (t *TestFlags) TestConfigFromFlags() (*config.TestConfig, error) {
	var cfg config.TestConfig

	if t.flagTFOutputDir != "" {
		var tfOutput map[string]tfOutputItem
		testConfigMap := make(map[string]interface{})
		cmd := exec.Command("terraform", "output", "-state", fmt.Sprintf("%s/terraform.tfstate", t.flagTFOutputDir), "-json")
		cmdOutput, err := cmd.CombinedOutput()
		if err != nil {
			return nil, err
		}
		err = json.Unmarshal(cmdOutput, &tfOutput)
		if err != nil {
			return nil, err
		}

		for k, v := range tfOutput {
			if k == "private_subnets" {
				testConfigMap["subnets"] = v.Value
			} else {
				testConfigMap[k] = v.Value
			}
		}
		testConfigJSON, err := json.Marshal(testConfigMap)
		if err != nil {
			return nil, err
		}
		err = json.Unmarshal(testConfigJSON, &cfg)
		if err != nil {
			fmt.Println("error unmarshalling", err)
		}
	} else {
		cfg = config.TestConfig{
			NoCleanupOnFailure: t.flagNoCleanupOnFailure,
			ECSClusterARN:      t.flagECSClusterARN,
			Subnets:            t.flagSubnets,
			Region:             t.flagRegion,
			LogGroupName:       t.flagLogGroupName,
			Tags:               t.flagTFTags,
		}
	}

	cfg.NoCleanupOnFailure = t.flagNoCleanupOnFailure

	return &cfg, nil
}
