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

	// If there is a terraform output directory, use that to create test config.
	if t.flagTFOutputDir != "" {
		// We use tfOutput to parse the terraform output.
		// We then read the parsed output and put into tfOutputValues,
		// extracting only Values from the output.
		var tfOutput map[string]tfOutputItem
		tfOutputValues := make(map[string]interface{})

		// Get terraform output as JSON.
		cmd := exec.Command("terraform", "output", "-state", fmt.Sprintf("%s/terraform.tfstate", t.flagTFOutputDir), "-json")
		cmdOutput, err := cmd.CombinedOutput()
		if err != nil {
			return nil, err
		}

		// Parse terraform output into tfOutput map.
		err = json.Unmarshal(cmdOutput, &tfOutput)
		if err != nil {
			return nil, err
		}

		// Extract Values from the parsed output into a separate map.
		for k, v := range tfOutput {
			tfOutputValues[k] = v.Value
		}

		// Marshal the resulting map back into JSON so that
		// we can unmarshal it into the TestConfig struct directly.
		testConfigJSON, err := json.Marshal(tfOutputValues)
		if err != nil {
			return nil, err
		}
		err = json.Unmarshal(testConfigJSON, &cfg)
		if err != nil {
			return nil, err
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
