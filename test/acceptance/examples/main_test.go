// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package examples

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	terratestLogger "github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios"
	clusterpeering "github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/cluster-peering"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/ec2"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/fargate"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/hcp"
	localityawarerouting "github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/locality-aware-routing"
	sameness "github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/service-sameness"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/examples/scenarios/wan-federation"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type ScenarioFunc func(string) scenarios.Scenario

var scenarioFuncs = map[string]ScenarioFunc{
	"FARGATE":                fargate.New,
	"EC2":                    ec2.New,
	"HCP":                    hcp.New,
	"CLUSTER_PEERING":        clusterpeering.New,
	"WAN_FEDERATION":         wan.New,
	"LOCALITY_AWARE_ROUTING": localityawarerouting.New,
	"SERVICE_SAMENESS":       sameness.New,
}

// TestRunScenario accepts a single scenario name as an environment
// variable and executes tests for the same. We want to run each
// scenario as a separate GitHub Action job.
func TestRunScenario(t *testing.T) {
	scenarioName := os.Getenv("TEST_SCENARIO")
	require.NotEmpty(t, scenarioName)

	scenario := getScenario(scenarioName)
	require.NotNil(t, scenario, "unexpected scenario name")

	initOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: fmt.Sprintf("../../../examples/%s", scenario.GetFolderName()),
		NoColor:      true,
	})
	terraform.Init(t, initOptions)

	var tfVars map[string]interface{}
	retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		var err error
		tfVars, err = scenario.GetTerraformVars()
		require.NoError(r, err)
	})

	applyOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: initOptions.TerraformDir,
		Vars:         tfVars,
		NoColor:      true,
	})

	t.Cleanup(func() {
		if os.Getenv("NO_CLEANUP_ON_FAILURE") != "true" {
			terraform.Destroy(t, applyOptions)
		}
	})
	terraform.Apply(t, applyOptions)

	outputs := terraform.OutputAll(t, &terraform.Options{
		TerraformDir: initOptions.TerraformDir,
		NoColor:      true,
		Logger:       terratestLogger.Default,
	})

	logger.Log(t, "running validation for scenario")
	scenario.Validate(t, outputs)
	logger.Log(t, "validation successful!!")
}

func getScenario(name string) scenarios.Scenario {
	// This name will be passed as the name input to the terraform apply call.
	// This name can be modified inside the individual scenarios too according
	// to the scenario's needs.
	terraformResourcesName := fmt.Sprintf("ecs-%s", strings.ToLower(random.UniqueId()))

	if scenario, ok := scenarioFuncs[name]; ok {
		return scenario(terraformResourcesName)
	}

	return nil
}
