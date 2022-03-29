package config

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"reflect"
	"strings"
)

// TestConfig holds configuration for the test suite.
type TestConfig struct {
	NoCleanupOnFailure bool
	ECSClusterARN      string      `json:"ecs_cluster_arn"`
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
}

func (t TestConfig) TFVars(ignoreVars ...string) map[string]interface{} {
	vars := map[string]interface{}{
		"ecs_cluster_arn": t.ECSClusterARN,
		"launch_type":     t.LaunchType,
		"subnets":         t.Subnets,
		"region":          t.Region,
		"log_group_name":  t.LogGroupName,
		"vpc_id":          t.VpcID,
		"route_table_ids": t.RouteTableIDs,
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

// UnmarshalTF populates the cfg struct with the Terraform outputs
// from the given tfDir directory. The cfg arg must be a pointer to
// a value that can be populated by json.Unmarshal based on the output
// of the `terraform output -json` command.
func UnmarshalTF(tfDir string, cfg interface{}) error {
	type tfOutputItem struct {
		Value interface{}
		Type  interface{}
	}
	// We use tfOutput to parse the terraform output.
	// We then read the parsed output and put into tfOutputValues,
	// extracting only Values from the output.
	var tfOutput map[string]tfOutputItem
	tfOutputValues := make(map[string]interface{})

	// Get terraform output as JSON.
	cmd := exec.Command("terraform", "output", "-state", fmt.Sprintf("%s/terraform.tfstate", tfDir), "-json")
	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		return err
	}

	// Parse terraform output into tfOutput map.
	err = json.Unmarshal(cmdOutput, &tfOutput)
	if err != nil {
		return err
	}

	// Extract Values from the parsed output into a separate map.
	for k, v := range tfOutput {
		tfOutputValues[k] = v.Value
	}

	// Marshal the resulting map back into JSON so that
	// we can unmarshal it into the target struct directly.
	configJSON, err := json.Marshal(tfOutputValues)
	if err != nil {
		return err
	}
	return json.Unmarshal(configJSON, &cfg)
}

// TFVars converts the given struct to a map[string]interface that
// is suitable for supplying to terraform ... -var=...
// It iterates over the fields in the struct and creates a key for each field with a json tag.
//
// ignoreVars is optional and if provided any matching fields will be
// not be returned in the map.
//
// The argument i must be a struct value or a pointer to a struct; otherwise,
// the function will panic.
func TFVars(i interface{}, ignoreVars ...string) map[string]interface{} {
	v := reflect.ValueOf(i)
	if v.Kind() == reflect.Ptr {
		v = v.Elem()
	}
	t := v.Type()
	if t.Kind() != reflect.Struct {
		panic("input must be a struct or pointer to a struct")
	}

	vars := make(map[string]interface{})
	structVars(i, vars)
	for _, v := range ignoreVars {
		delete(vars, v)
	}
	return vars
}

func structVars(i interface{}, m map[string]interface{}) {
	v := reflect.ValueOf(i)
	t := v.Type()
	for i := 0; i < t.NumField(); i++ {
		f := t.Field(i)
		if f.Type.Kind() == reflect.Ptr || f.Type.Kind() == reflect.Struct {
			// if the embedded field is a ptr or a struct recurse it
			structVars(v.Field(i).Interface(), m)
		} else {
			tag := t.Field(i).Tag.Get("json")
			if tag != "" {
				name := strings.Split(tag, ",")
				m[name[0]] = v.Field(i).Interface()
			}
		}
	}
}
