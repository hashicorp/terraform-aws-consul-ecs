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
