// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package examples

import (
	"fmt"
	"os"
	"testing"
	"time"

	terratestLogger "github.com/gruntwork-io/terratest/modules/logger"
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

// TestRunScenario accepts a single scenario name as an environment
// variable and executes tests for the same. We want to run each
// scenario as a separate GitHub Action job.
func TestRunScenario(t *testing.T) {
	// Setup scenario registry
	scenarioRegistry := setupScenarios()

	scenarioName := os.Getenv("TEST_SCENARIO")
	require.NotEmpty(t, scenarioName)

	scenario, err := scenarioRegistry.Retrieve(scenarioName)
	require.NoError(t, err)

	initOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: fmt.Sprintf("../../../examples/%s", scenario.FolderName),
		NoColor:      true,
	})
	terraform.Init(t, initOptions)

	var tfVars map[string]interface{}
	retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		var err error
		tfVars, err = scenario.TerraformInputVars()
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

func setupScenarios() scenarios.ScenarioRegistry {
	reg := scenarios.NewScenarioRegistry()

	fargate.RegisterScenario(reg)
	ec2.RegisterScenario(reg)
	clusterpeering.RegisterScenario(reg)
	hcp.RegisterScenario(reg)
	sameness.RegisterScenario(reg)
	wan.RegisterScenario(reg)
	localityawarerouting.RegisterScenario(reg)

	return reg
}
