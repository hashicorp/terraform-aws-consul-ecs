package perf

import (
	"encoding/json"
	"fmt"
	"testing"

	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/stretchr/testify/require"
)

type TerraformOutputVariables struct {
	BootstrapToken string
	ConsulELBURL   string
}

type rawTerraformOutputVariables = map[string]struct {
	Sensitive bool   `json:"sensitive"`
	Type      string `json:"type"`
	Value     string `json:"value"`
}

func (config TestConfig) terraformInit(t *testing.T) {
	runTerraform(t, []string{"init"})
}

func (config TestConfig) terraformApply(t *testing.T, initSetup bool) {
	args := []string{
		"destroy",
		"-auto-approve",
		fmt.Sprintf("-var-file=%s", config.ConfigPath),
	}

	if !initSetup {
		args = append(args,
			"-var=server_instances_per_group=0",
			"-var=client_instances_per_group=0",
		)
	}

	runTerraform(t, args)
}

func terraformOutput(t *testing.T) TerraformOutputVariables {
	outputVariables := make(rawTerraformOutputVariables)

	out := runTerraform(t, []string{"output", "--json"})
	err := json.Unmarshal([]byte(out), &outputVariables)
	require.NoError(t, err)

	return TerraformOutputVariables{
		BootstrapToken: getValue(t, outputVariables, "bootstrap_token"),
		ConsulELBURL:   getValue(t, outputVariables, "consul_elb_url"),
	}
}

func runTerraform(t *testing.T, args []string) string {
	return shell.RunCommandAndGetOutput(t, shell.Command{
		WorkingDir: "./setup",
		Command:    "terraform",
		Args:       args,
	})
}

func getValue(t *testing.T, raw rawTerraformOutputVariables, v string) string {
	valueData, ok := raw[v]
	require.True(t, ok)
	return valueData.Value
}
