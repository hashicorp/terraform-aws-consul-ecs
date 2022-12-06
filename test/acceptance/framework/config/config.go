package config

// TestConfig holds configuration for the test suite.
type TestConfig struct {
	NoCleanupOnFailure bool
	ECSClusterARNs     []string    `json:"ecs_cluster_arns"`
	LaunchType         string      `json:"launch_type"`
	Subnets            interface{} `json:"subnets"`
	Suffix             string
	Region             string   `json:"region"`
	VpcID              string   `json:"vpc_id"`
	RouteTableIDs      []string `json:"route_table_ids"`
	LogGroupName       string   `json:"log_group_name"`
	Tags               interface{}
	ClientServiceName  string
	ServerServiceName  string
	ConsulVersion      string `json:"consul_version"`
}

func (t TestConfig) TFVars(ignoreVars ...string) map[string]interface{} {
	vars := map[string]interface{}{
		"ecs_cluster_arns": t.ECSClusterARNs,
		"launch_type":      t.LaunchType,
		"subnets":          t.Subnets,
		"region":           t.Region,
		"log_group_name":   t.LogGroupName,
		"vpc_id":           t.VpcID,
		"route_table_ids":  t.RouteTableIDs,
		"consul_version":   t.ConsulVersion,
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
