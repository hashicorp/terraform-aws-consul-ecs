// Copyright IBM Corp. 2026
// SPDX-License-Identifier: MPL-2.0

package validation

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

func TestConsulVersionCompatibility(t *testing.T) {
	t.Parallel()

	// Evaluate the module's actual version locals without initializing its AWS resources.
	source, err := os.ReadFile("../../../../modules/dev-server/consul_1_14_compat.tf")
	require.NoError(t, err)
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "compat.tf"), source, 0600))
	require.NoError(t, os.WriteFile(filepath.Join(dir, "variables.tf"), []byte(`
variable "consul_image" {
  type = string
}

output "is_consul_1_14_plus" {
  value = local.is_consul_1_14_plus
}
`), 0600))

	terraform.Init(t, &terraform.Options{
		TerraformDir: dir,
		NoColor:      true,
	})

	for _, tc := range []struct {
		image string
		want  string
	}{
		{"hashicorp/consul:1.13.9", "false"},
		{"hashicorp/consul:1.14.0", "true"},
		{"public.ecr.aws/hashicorp/consul:1.21.5", "true"},
		{"public.ecr.aws/hashicorp/consul-enterprise:1.21.12-ent", "true"},
		{"public.ecr.aws/hashicorp/consul:2.0.4", "true"},
		{"public.ecr.aws/hashicorp/consul-enterprise:2.0.4-ent", "true"},
		{"public.ecr.aws/hashicorp/consul:2.1.0", "true"},
		{"public.ecr.aws/hashicorp/consul-enterprise:2.1.0-ent", "true"},
		{"registry.example.com:5000/consul:2.0.4", "true"},
	} {
		t.Run(tc.image, func(t *testing.T) {
			out := terraform.Plan(t, &terraform.Options{
				TerraformDir: dir,
				NoColor:      true,
				Vars: map[string]interface{}{
					"consul_image": tc.image,
				},
			})
			require.Contains(t, out, "+ is_consul_1_14_plus = "+tc.want)
		})
	}
}
