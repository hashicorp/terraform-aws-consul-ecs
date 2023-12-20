// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package scenarios

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRegistry_ScenarioExists(t *testing.T) {
	registry := NewScenarioRegistry()
	registry.Register(getTestScenarioRegistrationPayload())

	_, err := registry.Retrieve("TEST_SCENARIO")
	require.Error(t, err)
}

func TestRegistry_Register_InvalidScenarioName(t *testing.T) {
	registry := NewScenarioRegistry()
	scenario := getTestScenarioRegistrationPayload()
	scenario.Name = ""
	err := registry.Register(scenario)
	require.Error(t, err)
}

func TestRegistry_Register_InvalidFolderName(t *testing.T) {
	registry := NewScenarioRegistry()
	scenario := getTestScenarioRegistrationPayload()
	scenario.FolderName = ""
	err := registry.Register(scenario)
	require.Error(t, err)
}

func TestRegistry_Register_InvalidInputVarHook(t *testing.T) {
	registry := NewScenarioRegistry()
	scenario := getTestScenarioRegistrationPayload()
	scenario.TerraformInputVars = nil
	err := registry.Register(scenario)
	require.Error(t, err)
}

func TestRegistry_Register_InvalidValidateHook(t *testing.T) {
	registry := NewScenarioRegistry()
	scenario := getTestScenarioRegistrationPayload()
	scenario.Validate = nil
	err := registry.Register(scenario)
	require.Error(t, err)
}

func TestRegistry_RegisterAndRetrieve(t *testing.T) {
	registry := NewScenarioRegistry()
	scenario := getTestScenarioRegistrationPayload()
	err := registry.Register(scenario)
	require.NoError(t, err)

	actualScenario, err := registry.Retrieve("TEST_SCENARIO")
	require.NoError(t, err)
	require.Equal(t, scenario.Name, actualScenario.Name)
	require.Equal(t, scenario.FolderName, actualScenario.FolderName)
}

func getTestScenarioRegistrationPayload() ScenarioRegistration {
	return ScenarioRegistration{
		Name:       "TEST_SCENARIO",
		FolderName: "test_folder/test_scenario",
		TerraformInputVars: func() (map[string]interface{}, error) {
			return nil, nil
		},
		Validate: func(t *testing.T, b []byte) {},
	}
}
