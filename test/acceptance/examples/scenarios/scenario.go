// Copyright IBM Corp. 2021, 2025
// SPDX-License-Identifier: MPL-2.0

package scenarios

import (
	"fmt"
	"testing"
)

// ScenarioRegistry helps us interact with the
// actual registry that holds details about the scenarios.
type ScenarioRegistry interface {
	// Register registers a scenario into the registry
	Register(ScenarioRegistration)

	// Retrieve retrieves a scenario from the registry
	Retrieve(name string) (ScenarioRegistration, error)
}

type TerraformInputVarsHook func() (map[string]interface{}, error)
type ValidateHook func(*testing.T, []byte)

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

func (r *ScenarioRegistration) validate() error {
	if r.Name == "" {
		return fmt.Errorf("scenario name cannot be empty")
	}

	if r.FolderName == "" {
		return fmt.Errorf("scenario %s should have a folder name associated to it", r.Name)
	}

	if r.TerraformInputVars == nil {
		return fmt.Errorf("scenario %s should provide hooks for providing terraform input variables", r.Name)
	}

	if r.Validate == nil {
		return fmt.Errorf("scenario %s should provide hooks validating the deployment", r.Name)
	}

	return nil
}
