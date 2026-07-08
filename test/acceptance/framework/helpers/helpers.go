// Copyright IBM Corp. 2021, 2026
// SPDX-License-Identifier: MPL-2.0

package helpers

import (
	"fmt"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
)

// ExecuteRemoteCommand executes a command inside a container in the task specified
// by taskARN.
func ExecuteRemoteCommand(t *testing.T, testConfig *config.TestConfig, clusterARN, taskARN, container, command string) (string, error) {
	out, err := shell.RunCommandAndGetOutputE(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"execute-command",
			"--region",
			testConfig.Region,
			"--cluster",
			clusterARN,
			"--task",
			taskARN,
			fmt.Sprintf("--container=%s", container),
			"--command",
			command,
			"--interactive",
		},
	})
	// session-manager-plugin exits non-zero with "Cannot perform start session: EOF"
	// when the interactive session closes after the command completes. The command
	// output is still captured in `out`, so this is a false error — not a real failure.
	if err != nil && strings.Contains(out, "Cannot perform start session: EOF") {
		return out, nil
	}
	return out, err
}
