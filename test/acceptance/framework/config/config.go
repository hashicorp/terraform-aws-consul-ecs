package config

// TestConfig holds configuration for the test suite
type TestConfig struct {
	NoCleanupOnFailure bool
	ClusterARN         string
	Subnets            string
	Suffix             string
	Region             string
	LogGroupName       string
	Tags               string
}

func (t TestConfig) TFVars() map[string]interface{} {
	vars := map[string]interface{}{
		"ecs_cluster_arn": t.ClusterARN,
		"subnets":         t.Subnets,
		"suffix":          t.Suffix,
		"region":          t.Region,
		"log_group_name":  t.LogGroupName,
	}

	// If the flag is an empty string or object then terratest
	// passes '-var tags=' which errors out in Terraform so instead
	// we don't set tags and so it never passes the tags var and so
	// Terraform uses the variable's default which works.
	if t.Tags != "" && t.Tags != "{}" {
		vars["tags"] = t.Tags
	}
	return vars
}
