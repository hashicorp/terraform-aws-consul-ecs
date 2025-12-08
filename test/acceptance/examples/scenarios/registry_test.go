// Copyright IBM Corp. 2021, 2025
// SPDX-License-Identifier: MPL-2.0

package scenarios

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRegistry(t *testing.T) {
	cases := map[string]struct {
		scenarioPresent  bool
		registerScenario bool
		mutateScenario   func(ScenarioRegistration) ScenarioRegistration
		shouldPanic      bool
		wantErr          bool
	}{
		"scenario already present": {
			scenarioPresent:  true,
			registerScenario: true,
			shouldPanic:      true,
		},
		"scenario not present": {
			wantErr: true,
		},
		"invalid scenario name": {
			mutateScenario: func(sr ScenarioRegistration) ScenarioRegistration {
				sr.Name = ""
				return sr
			},
			registerScenario: true,
			shouldPanic:      true,
		},
		"invalid scenario folder name": {
			mutateScenario: func(sr ScenarioRegistration) ScenarioRegistration {
				sr.FolderName = ""
				return sr
			},
			registerScenario: true,
			shouldPanic:      true,
		},
		"invalid scenario TF Vars hook": {
			mutateScenario: func(sr ScenarioRegistration) ScenarioRegistration {
				sr.TerraformInputVars = nil
				return sr
			},
			registerScenario: true,
			shouldPanic:      true,
		},
		"invalid scenario Validate hook": {
			mutateScenario: func(sr ScenarioRegistration) ScenarioRegistration {
				sr.Validate = nil
				return sr
			},
			registerScenario: true,
			shouldPanic:      true,
		},
		"successful registration and retrieval": {
			registerScenario: true,
		},
	}

	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			defer func() {
				if r := recover(); r != nil {
					t.Logf("Panic caught: %v", r)
				}
			}()

			registry := NewScenarioRegistry()

			if c.scenarioPresent {
				registry.Register(getTestScenarioRegistrationPayload())
			}

			payload := getTestScenarioRegistrationPayload()
			if c.mutateScenario != nil {
				payload = c.mutateScenario(payload)
			}

			if c.registerScenario {
				registry.Register(payload)
			}

			actualScenario, err := registry.Retrieve("TEST_SCENARIO")
			if c.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				require.Equal(t, payload.Name, actualScenario.Name)
				require.Equal(t, payload.FolderName, actualScenario.FolderName)
			}

			// If the test is supposed to panic while registering
			// a scenario and we reach here, we fail explicitly.
			if c.shouldPanic {
				t.FailNow()
			}
		})
	}
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
