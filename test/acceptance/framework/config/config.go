// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package config

// TestConfig holds configuration for the test suite.
type TestConfig struct {
	NoCleanupOnFailure bool
	ECSClusterARNs     []string    `json:"ecs_cluster_arns"`
	LaunchType         string      `json:"launch_type"`
	PrivateSubnets     interface{} `json:"private_subnets"`
	PublicSubnets      interface{} `json:"public_subnets"`
	Suffix             string
	Region             string   `json:"region"`
	VpcID              string   `json:"vpc_id"`
	RouteTableIDs      []string `json:"route_table_ids"`
	LogGroupName       string   `json:"log_group_name"`
	Tags               interface{}
	ClientServiceName  string
	ServerServiceName  string
	// ConsulVersion is the default Consul version used when edition-specific versions are not set.
	// Deprecated: Use ConsulCEVersion or ConsulEnterpriseVersion for edition-specific versions.
	ConsulVersion           string `json:"consul_version"`
	ConsulCEVersion         string `json:"consul_ce_version"`
	ConsulEnterpriseVersion string `json:"consul_enterprise_version"`
}

func (t TestConfig) TFVars(ignoreVars ...string) map[string]interface{} {
	vars := map[string]interface{}{
		"ecs_cluster_arns": t.ECSClusterARNs,
		"launch_type":      t.LaunchType,
		"private_subnets":  t.PrivateSubnets,
		"public_subnets":   t.PublicSubnets,
		"region":           t.Region,
		"log_group_name":   t.LogGroupName,
		"vpc_id":           t.VpcID,
		"route_table_ids":  t.RouteTableIDs,
	}

	// If the flag is an empty string or object then terratest
	// passes '-var tags=' which errors out in Terraform so instead
	// we don't set tags and so it never passes the tags var and so
	// Terraform uses the variable's default which works.
	if t.Tags != "" && t.Tags != "{}" {
		vars["tags"] = t.Tags
	}

	for _, v := range ignoreVars {
		delete(vars, v)
	}
	return vars
}

// ConsulImageURI returns the Consul image URI for the configured consul version.
// It uses edition-specific versions (ConsulCEVersion or ConsulEnterpriseVersion) if available,
// falling back to the generic ConsulVersion for backward compatibility.
func (t TestConfig) ConsulImageURI(enterprise bool) string {
	var version string
	if enterprise {
		// Use Enterprise-specific version if set, otherwise fall back to ConsulVersion
		if t.ConsulEnterpriseVersion != "" {
			version = t.ConsulEnterpriseVersion
		} else {
			version = t.ConsulVersion
		}
		return "public.ecr.aws/hashicorp/consul-enterprise:" + version + "-ent"
	}
	// Use CE-specific version if set, otherwise fall back to ConsulVersion
	if t.ConsulCEVersion != "" {
		version = t.ConsulCEVersion
	} else {
		version = t.ConsulVersion
	}
	return "public.ecr.aws/hashicorp/consul:" + version
}
