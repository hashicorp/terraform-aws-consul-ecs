package helpers

import (
	"fmt"
	"testing"

	terratestLogger "github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
)

// ExecuteRemoteCommand executes a command inside a container in the task specified
// by taskARN.
func ExecuteRemoteCommand(t *testing.T, testConfig *config.TestConfig, taskARN, container, command string) (string, error) {
	return shell.RunCommandAndGetOutputE(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"execute-command",
			"--region",
			testConfig.Region,
			"--cluster",
			testConfig.ECSClusterARN,
			"--task",
			taskARN,
			fmt.Sprintf("--container=%s", container),
			"--command",
			command,
			"--interactive",
		},
		Logger: terratestLogger.New(logger.TestLogger{}),
	})
}
