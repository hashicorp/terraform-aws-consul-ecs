// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package scenarios

import "testing"

// Scenario is the interface we expect individual example scenarios
// present in this repository to implement.
type Scenario interface {
	// The name of the example's folder under the `examples/` directory
	GetFolderName() string

	// List of TF variables that needs to be supplied to the
	// example's terraform config.
	GetTerraformVars() (map[string]interface{}, error)

	// Validations that needs to be performed on the deployment. This
	// hook will only be called after a successful terraform apply.
	Validate(t *testing.T, tfOutput map[string]interface{})
}

// ScenarioRegistry helps us interact with the
// actual registry that holds details about the scenarios.
type ScenarioRegistry interface {
	// Register registers a scenario into the registry
	Register(ScenarioRegistration) error

	// Retrieve retrieves a scenario from the registry
	Retrieve(name string) (ScenarioRegistration, error)
}

type TerraformInputVarsHook func() (map[string]interface{}, error)
type ValidateHook func(t *testing.T, tfOutput map[string]interface{})

// ScenarioRegistration is the struct we expect each individual
// scenario to use and register themselves by providing valid
// lifecycle hooks
type ScenarioRegistration struct {
	// The name of the scenario. This name should match the value
	// of TEST_SCENARIO environment variable which the test uses
	// to determine the scenario to run.
	Name string

	// The name of the example's folder under the `examples/` directory
	FolderName string

	// List of TF variables that needs to be supplied to the
	// example's terraform config.
	TerraformInputVars TerraformInputVarsHook

	// Validate is the hook called when validations need to be performed on the deployment. This
	// hook will only be called after a successful terraform apply.
	Validate ValidateHook
}
