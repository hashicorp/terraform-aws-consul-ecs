// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package scenarios

import "fmt"

type scenarioName string

type registry struct {
	scenarios map[scenarioName]ScenarioRegistration
}

func NewScenarioRegistry() ScenarioRegistry {
	return &registry{
		scenarios: make(map[scenarioName]ScenarioRegistration),
	}
}

func (s *registry) Register(reg ScenarioRegistration) {
	if _, ok := s.scenarios[scenarioName(reg.Name)]; ok {
		panic(fmt.Sprintf("scenario %s already registered", reg.Name))
	}

	if err := reg.validate(); err != nil {
		panic(fmt.Errorf("error validating scenario %w", err))
	}

	s.scenarios[scenarioName(reg.Name)] = reg
}

func (s *registry) Retrieve(name string) (ScenarioRegistration, error) {
	scenario, ok := s.scenarios[scenarioName(name)]
	if !ok {
		return ScenarioRegistration{}, fmt.Errorf("scenario %s is not registered", name)
	}

	return scenario, nil
}
