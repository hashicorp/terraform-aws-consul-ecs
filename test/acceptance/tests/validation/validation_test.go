// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package validation

import (
	"context"
	"fmt"
	"regexp"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// TestVolumeVariable tests passing a list of volumes to mesh-task.
// This validates a big nested dynamic block in mesh-task.
func TestVolumeVariable(t *testing.T) {
	t.Parallel()
	volumes := []map[string]interface{}{
		{
			"name": "my-vol1",
		},
		{
			"name":      "my-vol2",
			"host_path": "/tmp/fake/path",
		},
		{
			"name":                        "no-optional-fields",
			"docker_volume_configuration": map[string]interface{}{},
			"efs_volume_configuration": map[string]interface{}{
				"file_system_id": "fakeid123",
			},
		},
		{
			"name": "all-the-fields",
			"docker_volume_configuration": map[string]interface{}{
				"scope":         "shared",
				"autoprovision": true,
				"driver":        "local",
				"driver_opts": map[string]interface{}{
					"type":   "nfs",
					"device": "host.example.com:/",
					"o":      "addr=host.example.com,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport",
				},
			},
			"fsx_windows_file_server_volume_configuration": map[string]interface{}{
				"file_system_id": "fakeid456",
				"root_directory": `\\data`,
				"authorization_config": map[string]interface{}{
					"credentials_parameter": "arn:aws:secretsmanager:us-east-1:000000000000:secret:fake-fake-fake-fake",
					"domain":                "domain-name",
				},
			},
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/volume-variable",
		Vars:         map[string]interface{}{"volumes": volumes},
		NoColor:      true,
	}
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	terraform.InitAndPlan(t, terraformOptions)
}

// TestPassingExistingRoles will create the task definitions to validate
// creation and passing of IAM roles by mesh-task. It creates two task definitions
// with mesh-task:
//   - one which has mesh-task create the roles
//   - one which passes in existing roles
//
// This test does not start any services.
//
// Note: We don't have a validation for create_task_role=true XOR task_role=<non-null>.
//
//	If the role is created as part of the terraform plan/apply and passed in to mesh-task,
//	then the role is an unknown value during the plan, since it is not yet created, and you
//	can't reliably test its value for validations.
func TestPassingExistingRoles(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/pass-existing-iam-roles",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	// Init AWS clients.
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("us-west-2"))
	require.NoError(t, err, "unable to initialize ECS client")
	ecsClient := ecs.NewFromConfig(cfg)
	iamClient := iam.NewFromConfig(cfg)

	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	terraform.InitAndApply(t, terraformOptions)

	outputs := terraform.OutputAll(t, terraformOptions)
	suffix := outputs["suffix"].(string)

	{
		// Check that mesh-task creates roles by default.
		taskDefArn := outputs["create_roles_task_definition_arn"].(string)
		family := outputs["create_roles_family"].(string)

		resp, err := ecsClient.DescribeTaskDefinition(ctx, &ecs.DescribeTaskDefinitionInput{
			TaskDefinition: &taskDefArn,
		})
		require.NoError(t, err)

		// Expected role names, as created by mesh-task
		expTaskRoleName := family + "-task"
		expExecRoleName := family + "-execution"

		// mesh-task should create roles and use them
		taskDef := resp.TaskDefinition
		require.NotNil(t, taskDef.TaskRoleArn)
		require.NotNil(t, taskDef.ExecutionRoleArn)
		require.Regexp(t, `arn:aws:iam::\d+:role/consul-ecs/`+expTaskRoleName, *taskDef.TaskRoleArn)
		require.Regexp(t, `arn:aws:iam::\d+:role/consul-ecs/`+expExecRoleName, *taskDef.ExecutionRoleArn)

		// Check that the roles were really created.
		for _, roleName := range []string{expTaskRoleName, expExecRoleName} {
			resp, err := iamClient.GetRole(ctx, &iam.GetRoleInput{RoleName: &roleName})
			require.NoError(t, err)
			require.Equal(t, *resp.Role.RoleName, roleName)
		}
	}

	{
		// Check that mesh-task uses the passed in roles and doesn't create roles when roles are passed in.
		taskDefArn := outputs["pass_roles_task_definition_arn"].(string)
		family := outputs["pass_roles_family"].(string)

		resp, err := ecsClient.DescribeTaskDefinition(ctx, &ecs.DescribeTaskDefinitionInput{
			TaskDefinition: &taskDefArn,
		})
		require.NoError(t, err)

		// mesh-task should use the passed in roles.
		taskDef := resp.TaskDefinition
		require.NotNil(t, taskDef.TaskRoleArn)
		require.NotNil(t, taskDef.ExecutionRoleArn)
		require.Regexp(t, `arn:aws:iam::\d+:role/consul-ecs-test-pass-task-role-`+suffix, *taskDef.TaskRoleArn)
		require.Regexp(t, `arn:aws:iam::\d+:role/consul-ecs-test-pass-execution-role-`+suffix, *taskDef.ExecutionRoleArn)

		// mesh-task should not create roles when they are passed in.
		expTaskRoleName := family + "-task"
		expExecRoleName := family + "-execution"
		for _, roleName := range []string{expTaskRoleName, expExecRoleName} {
			_, err := iamClient.GetRole(ctx, &iam.GetRoleInput{RoleName: &roleName})
			require.Error(t, err)
			require.Contains(t, err.Error(), "StatusCode: 404")
		}
	}

	t.Log("Test Successful!")
}

func TestValidation_AdditionalPolicies(t *testing.T) {
	t.Parallel()
	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/pass-role-additional-policies-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	cases := map[string]struct {
		execution bool
		errMsg    string
	}{
		"task": {
			execution: false,
			errMsg:    "ERROR: cannot set additional_task_role_policies when create_task_role=false",
		},
		"execution": {
			execution: true,
			errMsg:    "ERROR: cannot set additional_execution_role_policies when create_execution_role=false",
		},
	}
	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			_, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars: map[string]interface{}{
					"test_execution_role": c.execution,
				},
			})
			require.Error(t, err)
			// error messages are wrapped, so a space may turn into a newline.
			regex := strings.ReplaceAll(regexp.QuoteMeta(c.errMsg), " ", "\\s+")
			require.Regexp(t, regex, err.Error())
		})
	}
}

func TestPassingAppEntrypoint(t *testing.T) {
	t.Parallel()

	newint := func(x int) *int { return &x }
	cases := map[string]struct {
		value         *int
		expEntrypoint bool
	}{
		"null":     {nil, false},
		"negative": {newint(-1), false},
		"zero":     {newint(0), false},
		"one":      {newint(1), true},
		"five":     {newint(5), true},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/pass-app-entrypoint",
		NoColor:      true,
	}
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})

	terraform.Init(t, terraformOptions)
	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			opts := &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars:         map[string]interface{}{
					//"application_shutdown_delay_seconds": nil,
				},
			}
			if c.value != nil {
				opts.Vars["application_shutdown_delay_seconds"] = *c.value
			}
			out := terraform.Plan(t, opts)

			if c.expEntrypoint {
				// Look for app-entrypoint in the Terraform diff.
				regex := strings.Join([]string{
					`\+ entryPoint  = \[`,
					`  \+ "/consul/consul-ecs",`,
					`  \+ "app-entrypoint",`,
					`  \+ "-shutdown-delay",`,
					`  \+ "\d+s",`, // e.g. "2s", "10s", etc
					`\]`,
				}, `\s+`)
				require.Regexp(t, regex, out)
			} else {
				require.NotContains(t, out, "app-entrypoint")
			}

		})
	}
}

func TestValidation_UpstreamsVariable(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		upstreamsFile string
		errors        []string
	}{
		"no-upstreams": {
			upstreamsFile: "test-no-upstreams.json",
		},
		"valid-upstreams": {
			upstreamsFile: "test-valid-upstreams.json",
		},
		"invalid-upstreams": {
			upstreamsFile: "test-invalid-upstreams.json",
			errors: []string{
				"Upstream fields must be one of.*",
			},
		},
		"requires-destination-name": {
			upstreamsFile: "test-missing-destinationName.json",
			errors: []string{
				"Upstream fields .* are required.",
			},
		},
		"requires-local-bind-port": {
			upstreamsFile: "test-missing-localBindPort.json",
			errors: []string{
				"Upstream fields .* are required.",
			},
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/upstreams-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			out, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars: map[string]interface{}{
					"upstreams_file": c.upstreamsFile,
				},
			})

			if len(c.errors) == 0 {
				require.NoError(t, err)
			} else {
				require.Error(t, err)
				for _, regex := range c.errors {
					require.Regexp(t, regex, out)
				}
			}
		})
	}
}

func TestValidation_EnvoyPublicListenerPort(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		port  int
		error string
	}{
		"allowed-port": {
			port: 21000,
		},
		"too-high-port": {
			port:  65536,
			error: "The envoy_public_listener_port must be greater than 0 and less than or equal to 65535.",
		},
		"disallowed-port": {
			port:  19000,
			error: "The envoy_public_listener_port must not conflict with the following ports that are reserved for Consul and Envoy",
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/public-listener-port-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			out, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars: map[string]interface{}{
					"envoy_public_listener_port": c.port,
				},
			})

			if c.error == "" {
				require.NoError(t, err)
			} else {
				// handle multiline error messages.
				regex := strings.ReplaceAll(regexp.QuoteMeta(c.error), " ", "\\s+")
				require.Error(t, err)
				require.Regexp(t, regex, out)
			}
		})
	}
}

func TestValidation_EnvoyReadinessPort(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		port  int
		error string
	}{
		"allowed-port": {
			port: 23000,
		},
		"too-high-port": {
			port:  65536,
			error: "The envoy_readiness_port must be greater than 0 and less than or equal to 65535.",
		},
		"disallowed-port": {
			port:  19000,
			error: "The envoy_readiness_port must not conflict with the following ports that are reserved for Consul and Envoy",
		},
		"conflicts-with-listener-port": {
			port:  20000,
			error: "envoy_public_listener_port should not conflict with envoy_readiness_port",
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/envoy-readiness-port-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			out, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars: map[string]interface{}{
					"envoy_readiness_port": c.port,
				},
			})

			if c.error == "" {
				require.NoError(t, err)
			} else {
				// handle multiline error messages.
				regex := strings.ReplaceAll(regexp.QuoteMeta(c.error), " ", "\\s+")
				require.Error(t, err)
				require.Regexp(t, regex, out)
			}
		})
	}
}

func TestValidation_ConsulServiceName(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		serviceName string
		error       bool
	}{
		"empty": {},
		"lowercase": {
			serviceName: "lower-case-name",
		},
		"uppercase": {
			serviceName: "UPPER-CASE-NAME",
			error:       true,
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/service-name-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	for name, c := range cases {
		c := c

		t.Run(name, func(t *testing.T) {
			t.Parallel()

			out, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars: map[string]interface{}{
					"consul_service_name": c.serviceName,
				},
			})

			if c.error {
				require.Error(t, err)
				require.Regexp(t, "The consul_service_name must be lower case.", out)
			} else {
				require.NoError(t, err)
			}
		})
	}

}

func TestValidation_ConsulEcsConfigVariable(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		configFile string
		errors     []string
	}{
		"empty-map": {
			configFile: "test-empty-config.json",
		},
		"complete-config": {
			configFile: "test-complete-config.json",
		},
		"partial-config": {
			configFile: "test-partial-config.json",
		},
		"invalid-config": {
			configFile: "test-invalid-config.json",
			errors: []string{
				"Only the 'service', 'proxy', 'transparentProxy' and 'consulLogin' fields are allowed in consul_ecs_config.",
				"Only the 'enableTagOverride' and 'weights' fields are allowed in consul_ecs_config.service.",
				"Only the 'meshGateway', 'expose', and 'config' fields are allowed in consul_ecs_config.proxy.",
				"Only the 'mode' field is allowed in consul_ecs_config.proxy.meshGateway.",
				"Only the 'checks' and 'paths' fields are allowed in consul_ecs_config.proxy.expose.",
				"Only the 'listenerPort', 'path', 'localPathPort', and 'protocol' fields are allowed in each item of consul_ecs_config.proxy.expose.paths[*].",
				"Only the 'enabled', 'method', 'includeEntity', 'meta', 'region', 'stsEndpoint', and 'serverIdHeaderValue' fields are allowed in consul_ecs_config.consulLogin.",
			},
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/consul-ecs-config-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	for name, c := range cases {
		c := c

		t.Run(name, func(t *testing.T) {
			t.Parallel()

			out, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars: map[string]interface{}{
					"consul_ecs_config_file": c.configFile,
				},
			})

			if len(c.errors) == 0 {
				require.NoError(t, err)
			} else {
				for _, msg := range c.errors {
					// error messages are wrapped, so a space may turn into a newline.
					regex := strings.ReplaceAll(regexp.QuoteMeta(msg), " ", "\\s+")
					require.Regexp(t, regex, out)
				}
			}
		})
	}
}

func TestValidation_HTTPConfig(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		configFile string
		errors     []string
	}{
		"empty-map": {
			configFile: "test-empty-config.json",
		},
		"complete-config": {
			configFile: "test-complete-config.json",
		},
		"partial-config": {
			configFile: "test-partial-config.json",
		},
		"invalid-config": {
			configFile: "test-invalid-config.json",
			errors: []string{
				"Only the 'port', 'https', 'tls', 'tlsServerName' and 'caCertFile' fields are allowed in http_config.",
			},
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/http-config-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	for name, c := range cases {
		c := c

		t.Run(name, func(t *testing.T) {
			t.Parallel()

			out, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars: map[string]interface{}{
					"http_config_file": c.configFile,
				},
			})

			if len(c.errors) == 0 {
				require.NoError(t, err)
			} else {
				for _, msg := range c.errors {
					// error messages are wrapped, so a space may turn into a newline.
					regex := strings.ReplaceAll(regexp.QuoteMeta(msg), " ", "\\s+")
					require.Regexp(t, regex, out)
				}
			}
		})
	}
}

func TestValidation_GRPCConfig(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		configFile string
		errors     []string
	}{
		"empty-map": {
			configFile: "test-empty-config.json",
		},
		"complete-config": {
			configFile: "test-complete-config.json",
		},
		"partial-config": {
			configFile: "test-partial-config.json",
		},
		"invalid-config": {
			configFile: "test-invalid-config.json",
			errors: []string{
				"Only the 'port', 'tls', 'tlsServerName' and 'caCertFile' fields are allowed in grpc_config.",
			},
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/grpc-config-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	for name, c := range cases {
		c := c

		t.Run(name, func(t *testing.T) {
			t.Parallel()

			out, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars: map[string]interface{}{
					"grpc_config_file": c.configFile,
				},
			})

			if len(c.errors) == 0 {
				require.NoError(t, err)
			} else {
				for _, msg := range c.errors {
					// error messages are wrapped, so a space may turn into a newline.
					regex := strings.ReplaceAll(regexp.QuoteMeta(msg), " ", "\\s+")
					require.Regexp(t, regex, out)
				}
			}
		})
	}
}

// Test the validation that both partition and namespace must be provided or neither.
func TestValidation_NamespaceAndPartitionRequired(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		partition string
		namespace string
		errMsg    string
	}{
		"without partition and namespace": {
			partition: "",
			namespace: "",
			errMsg:    "",
		},
		"with partition and namespace": {
			partition: "default",
			namespace: "default",
			errMsg:    "",
		},
		"with partition, without namespace": {
			partition: "default",
			namespace: "",
			errMsg:    "ERROR: consul_namespace must be set if consul_partition is set",
		},
		"without partition, with namespace": {
			partition: "",
			namespace: "default",
			errMsg:    "ERROR: consul_partition must be set if consul_namespace is set",
		},
	}

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/admin-partition-validate",
		NoColor:      true,
	})
	_ = terraform.Init(t, terraformOptions)

	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			terraformOptions.Vars = map[string]interface{}{
				"partition": c.partition,
				"namespace": c.namespace,
			}
			t.Cleanup(func() {
				_, _ = terraform.DestroyE(t, terraformOptions)
			})
			_, err := terraform.PlanE(t, terraformOptions)
			if c.errMsg == "" {
				require.NoError(t, err)
			} else {
				require.Error(t, err)
				require.Contains(t, err.Error(), c.errMsg)
			}
		})
	}
}

func TestValidation_RolePath(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/role-path-validate",
		NoColor:      true,
	})
	_ = terraform.Init(t, terraformOptions)

	cases := []struct {
		path     string
		expError bool
	}{
		{"", true},
		{"test", true},
		{"/test", false},
		{"/test/", false},
	}
	for _, c := range cases {
		c := c
		t.Run(fmt.Sprintf("path=%q", c.path), func(t *testing.T) {
			t.Parallel()

			applyOpts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      terraformOptions.NoColor,
				Vars: map[string]interface{}{
					"iam_role_path": c.path,
				},
			})

			t.Cleanup(func() {
				_, _ = terraform.DestroyE(t, applyOpts)
			})
			_, err := terraform.PlanE(t, applyOpts)
			if c.expError {
				require.Error(t, err)
				require.Contains(t, err.Error(), "iam_role_path must begin with '/'")
			} else {
				require.NoError(t, err)
			}

		})
	}

}

func TestValidation_MeshGateway(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/mesh-gateway-validate",
		NoColor:      true,
	})
	_ = terraform.Init(t, terraformOptions)

	cases := map[string]struct {
		kind                    string
		enableMeshGatewayWANFed bool
		tls                     bool
		securityGroups          []string
		wanAddress              string
		lbEnabled               bool
		lbVpcID                 string
		lbSubnets               []string
		lbCreateSecGroup        bool
		lbModifySecGroup        bool
		lbModifySecGroupID      string
		expError                string
		gatewayCount            int
	}{
		"kind is required": {
			kind:                    "",
			enableMeshGatewayWANFed: false,
			expError:                `variable "kind" is not set`,
		},
		"kind must be mesh-gateway": {
			kind:                    "not-mesh-gateway",
			enableMeshGatewayWANFed: false,
			expError:                `Gateway kind must be one of 'mesh-gateway', 'terminating-gateway'`,
		},
		"no WAN federation": {
			kind:                    "mesh-gateway",
			enableMeshGatewayWANFed: false,
		},
		"mesh gateway WAN federation, no TLS": {
			kind:                    "mesh-gateway",
			enableMeshGatewayWANFed: true,
			tls:                     false,
			expError:                "tls must be true when enable_mesh_gateway_wan_federation is true",
		},
		"mesh gateway WAN federation": {
			kind:                    "mesh-gateway",
			enableMeshGatewayWANFed: true,
			tls:                     true,
		},
		"WAN address and LB enabled": {
			kind:                    "mesh-gateway",
			enableMeshGatewayWANFed: false,
			wanAddress:              "10.1.2.3",
			lbEnabled:               true,
			expError:                "Only one of wan_address or lb_enabled may be provided",
		},
		"lb_enabled": {
			kind:      "mesh-gateway",
			lbEnabled: true,
			lbSubnets: []string{"subnet"},
			lbVpcID:   "vpc",
		},
		"lb_enabled and no lb subnets": {
			kind:      "mesh-gateway",
			lbEnabled: true,
			lbVpcID:   "vpc",
			expError:  "lb_subnets is required when lb_enabled is true",
		},
		"lb_enabled and no VPC": {
			kind:      "mesh-gateway",
			lbEnabled: true,
			lbSubnets: []string{"subnet"},
			expError:  "lb_vpc_id is required when lb_enabled is true",
		},
		"lb create security group and modify security group": {
			kind:             "mesh-gateway",
			securityGroups:   []string{"sg"},
			lbEnabled:        true,
			lbSubnets:        []string{"subnet"},
			lbVpcID:          "vpc",
			lbCreateSecGroup: true,
			lbModifySecGroup: true,
			expError:         "Only one of lb_create_security_group or lb_modify_security_group may be true",
		},
		"lb modify security group and no security group ID": {
			kind:               "mesh-gateway",
			securityGroups:     []string{"sg"},
			lbEnabled:          true,
			lbSubnets:          []string{"subnet"},
			lbVpcID:            "vpc",
			lbCreateSecGroup:   false,
			lbModifySecGroup:   true,
			lbModifySecGroupID: "",
			expError:           "lb_modify_security_group_id is required when lb_modify_security_group is true",
		},
		"lb modify security group with security group ID": {
			kind:               "mesh-gateway",
			securityGroups:     []string{"sg"},
			lbEnabled:          true,
			lbSubnets:          []string{"subnet"},
			lbVpcID:            "vpc",
			lbCreateSecGroup:   false,
			lbModifySecGroup:   true,
			lbModifySecGroupID: "mod-sg",
		},
		"multiple gateways": {
			kind:         "mesh-gateway",
			lbEnabled:    true,
			lbSubnets:    []string{"subnet"},
			lbVpcID:      "vpc",
			gatewayCount: 2,
		},
	}
	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			tfVars := map[string]interface{}{
				"enable_mesh_gateway_wan_federation": c.enableMeshGatewayWANFed,
				"tls":                                c.tls,
				"security_groups":                    c.securityGroups,
				"wan_address":                        c.wanAddress,
				"lb_enabled":                         c.lbEnabled,
				"lb_subnets":                         c.lbSubnets,
				"lb_vpc_id":                          c.lbVpcID,
				"lb_create_security_group":           c.lbCreateSecGroup,
				"lb_modify_security_group":           c.lbModifySecGroup,
				"lb_modify_security_group_id":        c.lbModifySecGroupID,
			}
			if len(c.kind) > 0 {
				tfVars["kind"] = c.kind
			}
			if c.gatewayCount > 0 {
				tfVars["gateway_count"] = c.gatewayCount
			}
			applyOpts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      terraformOptions.NoColor,
				Vars:         tfVars,
			})
			t.Cleanup(func() { _, _ = terraform.DestroyE(t, applyOpts) })

			_, err := terraform.PlanE(t, applyOpts)
			if len(c.expError) > 0 {
				require.Error(t, err)
				require.Contains(t, err.Error(), c.expError)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestValidation_APIGateway(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/api-gateway-validate",
		NoColor:      true,
	})
	_ = terraform.Init(t, terraformOptions)

	cases := map[string]struct {
		kind           string
		lbEnabled      bool
		lbVpcID        string
		lbSubnets      []string
		expError       string
		customLBConfig []map[string]interface{}
		gatewayCount   int
	}{
		"kind is required": {
			kind:     "",
			expError: `variable "kind" is not set`,
		},
		"kind must be api-gateway": {
			kind:     "not-api-gateway",
			expError: `Gateway kind must be one of 'mesh-gateway', 'terminating-gateway'`,
		},
		"lb_enabled": {
			kind:      "api-gateway",
			lbEnabled: true,
			lbVpcID:   "test-lb-vpc-id",
			lbSubnets: []string{"subnet-1"},
		},
		"custom_lb_config passed with lb_enabled as true": {
			kind:      "api-gateway",
			lbEnabled: true,
			lbVpcID:   "test-lb-vpc-id",
			lbSubnets: []string{"subnet-1"},
			customLBConfig: []map[string]interface{}{
				{
					"target_group_arn": "test-arn-1",
					"container_name":   "test-container-1",
					"container_port":   9090,
				},
				{
					"target_group_arn": "test-arn-2",
					"container_name":   "test-container-2",
					"container_port":   9090,
				},
			},
			expError: "ERROR: custom_load_balancer_config must only be supplied when var.lb_enabled is false",
		},
		"custom_lb_config passed with lb_enabled as false": {
			kind:      "api-gateway",
			lbEnabled: false,
			customLBConfig: []map[string]interface{}{
				{
					"target_group_arn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/consul-ecs-api-gateway/3c01bdfe223245c9",
					"container_name":   "test-container-1",
					"container_port":   9090,
				},
				{
					"target_group_arn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/consul-ecs-api-gateway/3c01bdfe223245r4",
					"container_name":   "test-container-2",
					"container_port":   9090,
				},
			},
		},
		"multiple api gateways": {
			kind:         "api-gateway",
			lbEnabled:    true,
			lbVpcID:      "test-lb-vpc-id",
			lbSubnets:    []string{"subnet-1"},
			gatewayCount: 2,
		},
	}
	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			tfVars := map[string]interface{}{
				"lb_enabled": c.lbEnabled,
				"lb_vpc_id":  c.lbVpcID,
				"lb_subnets": c.lbSubnets,
			}
			if len(c.kind) > 0 {
				tfVars["kind"] = c.kind
			}
			if c.gatewayCount > 0 {
				tfVars["gateway_count"] = c.gatewayCount
			}
			if c.customLBConfig != nil {
				tfVars["custom_lb_config"] = c.customLBConfig
			}
			applyOpts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      terraformOptions.NoColor,
				Vars:         tfVars,
			})
			t.Cleanup(func() { _, _ = terraform.DestroyE(t, applyOpts) })

			_, err := terraform.PlanE(t, applyOpts)
			if len(c.expError) > 0 {
				require.Error(t, err)
				require.Contains(t, err.Error(), c.expError)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestValidation_TerminatingGateway(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/terminating-gateway-validate",
		NoColor:      true,
	})
	_ = terraform.Init(t, terraformOptions)

	cases := map[string]struct {
		kind         string
		expError     string
		gatewayCount int
	}{
		"kind is required": {
			kind:     "",
			expError: `variable "kind" is not set`,
		},
		"kind must be api-gateway": {
			kind:     "not-api-gateway",
			expError: `Gateway kind must be one of 'mesh-gateway', 'terminating-gateway'`,
		},
		"single terminating gateways": {
			kind: "terminating-gateway",
		},
		"multiple terminating gateways": {
			kind:         "terminating-gateway",
			gatewayCount: 2,
		},
	}
	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			tfVars := map[string]interface{}{}
			if len(c.kind) > 0 {
				tfVars["kind"] = c.kind
			}
			if c.gatewayCount > 0 {
				tfVars["gateway_count"] = c.gatewayCount
			}
			applyOpts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      terraformOptions.NoColor,
				Vars:         tfVars,
			})
			t.Cleanup(func() { _, _ = terraform.DestroyE(t, applyOpts) })

			_, err := terraform.PlanE(t, applyOpts)
			if len(c.expError) > 0 {
				require.Error(t, err)
				require.Contains(t, err.Error(), c.expError)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestValidation_TProxy(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		requiresCompatibilities []string
		disableTProxy           bool
		error                   bool
		errorStr                string
	}{
		"only EC2": {
			requiresCompatibilities: []string{"EC2"},
		},
		"only Fargate": {
			requiresCompatibilities: []string{"FARGATE"},
			error:                   true,
			errorStr:                "transparent proxy is supported only in ECS EC2 mode.",
		},
		"both Fargate and EC2": {
			requiresCompatibilities: []string{"FARGATE", "EC2"},
			error:                   true,
			errorStr:                "transparent proxy is supported only in ECS EC2 mode.",
		},
		"Consul DNS does not work without enabling tproxy": {
			requiresCompatibilities: []string{"FARGATE", "EC2"},
			disableTProxy:           true,
			error:                   true,
			errorStr:                "var.enable_transparent_proxy must be set to true for Consul DNS to be enabled.",
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/tproxy-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	for name, c := range cases {
		c := c

		t.Run(name, func(t *testing.T) {
			t.Parallel()

			vars := map[string]interface{}{
				"requires_compatibilities": c.requiresCompatibilities,
			}
			if c.disableTProxy {
				vars["enable_transparent_proxy"] = false
			}

			out, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars:         vars,
			})

			if c.error {
				require.Error(t, err)
				require.Regexp(t, c.errorStr, out)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestValidation_TProxy_Gateway(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		requiresCompatibilities []string
		disableTProxy           bool
		error                   bool
		errorStr                string
	}{
		"only EC2": {
			requiresCompatibilities: []string{"EC2"},
		},
		"only Fargate": {
			requiresCompatibilities: []string{"FARGATE"},
			error:                   true,
			errorStr:                "transparent proxy is supported only in ECS EC2 mode.",
		},
		"both Fargate and EC2": {
			requiresCompatibilities: []string{"FARGATE", "EC2"},
			error:                   true,
			errorStr:                "transparent proxy is supported only in ECS EC2 mode.",
		},
		"Consul DNS does not work without enabling tproxy": {
			requiresCompatibilities: []string{"FARGATE", "EC2"},
			disableTProxy:           true,
			error:                   true,
			errorStr:                "var.enable_transparent_proxy must be set to true for Consul DNS to be enabled.",
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/tproxy-gateway-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	for name, c := range cases {
		c := c

		t.Run(name, func(t *testing.T) {
			t.Parallel()

			vars := map[string]interface{}{
				"requires_compatibilities": c.requiresCompatibilities,
			}
			if c.disableTProxy {
				vars["enable_transparent_proxy"] = false
			}

			out, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars:         vars,
			})

			if c.error {
				require.Error(t, err)
				require.Regexp(t, c.errorStr, out)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

// TestVolumeVariableForGatewayModule tests passing a list of volumes to mesh-task.
// This validates a big nested dynamic block in mesh-task.
func TestVolumeVariableForGatewayModule(t *testing.T) {
	t.Parallel()
	volumes := []map[string]interface{}{
		{
			"name": "my-vol1",
		},
		{
			"name":      "my-vol2",
			"host_path": "/tmp/fake/path",
		},
		{
			"name":                        "no-optional-fields",
			"docker_volume_configuration": map[string]interface{}{},
			"efs_volume_configuration": map[string]interface{}{
				"file_system_id": "fakeid123",
			},
		},
		{
			"name": "all-the-fields",
			"docker_volume_configuration": map[string]interface{}{
				"scope":         "shared",
				"autoprovision": true,
				"driver":        "local",
				"driver_opts": map[string]interface{}{
					"type":   "nfs",
					"device": "host.example.com:/",
					"o":      "addr=host.example.com,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport",
				},
			},
			"fsx_windows_file_server_volume_configuration": map[string]interface{}{
				"file_system_id": "fakeid456",
				"root_directory": `\\data`,
				"authorization_config": map[string]interface{}{
					"credentials_parameter": "arn:aws:secretsmanager:us-east-1:000000000000:secret:fake-fake-fake-fake",
					"domain":                "domain-name",
				},
			},
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/volume-variable-gateway-validate",
		Vars:         map[string]interface{}{"volumes": volumes},
		NoColor:      true,
	}
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	terraform.InitAndPlan(t, terraformOptions)
}
