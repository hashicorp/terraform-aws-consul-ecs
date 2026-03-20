// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package config

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestConsulImageURI(t *testing.T) {
	tests := []struct {
		name       string
		config     TestConfig
		enterprise bool
		expected   string
	}{
		{
			name: "CE with specific version",
			config: TestConfig{
				ConsulCEVersion: "1.21.5",
			},
			enterprise: false,
			expected:   "public.ecr.aws/hashicorp/consul:1.21.5",
		},
		{
			name: "Enterprise with specific version",
			config: TestConfig{
				ConsulEnterpriseVersion: "1.21.9",
			},
			enterprise: true,
			expected:   "public.ecr.aws/hashicorp/consul-enterprise:1.21.9-ent",
		},
		{
			name: "CE fallback to ConsulVersion",
			config: TestConfig{
				ConsulVersion: "1.20.0",
			},
			enterprise: false,
			expected:   "public.ecr.aws/hashicorp/consul:1.20.0",
		},
		{
			name: "Enterprise fallback to ConsulVersion",
			config: TestConfig{
				ConsulVersion: "1.20.0",
			},
			enterprise: true,
			expected:   "public.ecr.aws/hashicorp/consul-enterprise:1.20.0-ent",
		},
		{
			name: "Prefer specific over generic",
			config: TestConfig{
				ConsulVersion:           "1.20.0",
				ConsulCEVersion:         "1.21.5",
				ConsulEnterpriseVersion: "1.21.9",
			},
			enterprise: true,
			expected:   "public.ecr.aws/hashicorp/consul-enterprise:1.21.9-ent",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			actual := tt.config.ConsulImageURI(tt.enterprise)
			assert.Equal(t, tt.expected, actual)
		})
	}
}
