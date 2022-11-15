package basic

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/helpers"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

// Test the validation that if TLS is enabled, Consul's CA certificate must also be provided.
func TestValidation_CACertRequiredIfTLSIsEnabled(t *testing.T) {
	t.Parallel()
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/ca-cert-validate",
		NoColor:      true,
	})
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	_, err := terraform.InitAndPlanE(t, terraformOptions)
	require.Error(t, err)
	require.Contains(t, err.Error(), "ERROR: consul_server_ca_cert_arn must be set if tls is true")
}

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

func TestValidation_ChecksVariable(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		checksFile string
		error      bool
	}{
		"no-checks": {
			checksFile: "test-no-checks.json",
		},
		"valid-checks": {
			checksFile: "test-valid-checks.json",
		},
		"invalid-checks": {
			checksFile: "test-invalid-checks.json",
			error:      true,
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/checks-validate",
		NoColor:      true,
	}
	terraform.Init(t, terraformOptions)

	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			out, err := terraform.PlanE(t, &terraform.Options{
				TerraformDir: terraformOptions.TerraformDir,
				NoColor:      true,
				Vars: map[string]interface{}{
					"checks_file": c.checksFile,
				},
			})

			if c.error {
				require.Error(t, err)
				require.Regexp(t, "Check fields must be one of.*", out)
			} else {
				require.NoError(t, err)
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
				"Only the 'service' and 'proxy' fields are allowed in consul_ecs_config.",
				"Only the 'enableTagOverride' and 'weights' fields are allowed in consul_ecs_config.service.",
				"Only the 'meshGateway', 'expose', and 'config' fields are allowed in consul_ecs_config.proxy.",
				"Only the 'mode' field is allowed in consul_ecs_config.proxy.meshGateway.",
				"Only the 'checks' and 'paths' fields are allowed in consul_ecs_config.proxy.expose.",
				"Only the 'listenerPort', 'path', 'localPathPort', and 'protocol' fields are allowed in each item of consul_ecs_config.proxy.expose.paths[*].",
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
	}{
		"kind is required": {
			kind:                    "",
			enableMeshGatewayWANFed: false,
			expError:                `variable "kind" is not set`,
		},
		"kind must be mesh-gateway": {
			kind:                    "not-mesh-gateway",
			enableMeshGatewayWANFed: false,
			expError:                `Gateway kind must be 'mesh-gateway'`,
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

func TestBasic(t *testing.T) {
	t.Parallel()

	cases := []struct {
		secure        bool
		enterprise    bool
		stateFile     string
		ecsClusterARN string
		datacenter    string
	}{
		{secure: false},
		{secure: true},
		{secure: true, enterprise: true},
	}

	cfg := suite.Config()
	require.GreaterOrEqual(t, len(cfg.ECSClusterARNs), len(cases),
		"TestBasic requires %d ECS clusters. Update setup-terraform and re-run.", len(cases),
	)

	initOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/basic-install",
		NoColor:      true,
	})
	terraform.Init(t, initOptions)

	for i, c := range cases {
		c := c

		// To support running in parallel, each test case should have:
		// - a unique cluster
		// - a unique Terrform state file to isolate resources
		// - a unique datacenter within the VPC to avoid conflicts in CloudMap namespaces
		// If more clusters are needed, update the cluster count in setup-terraform
		c.ecsClusterARN = cfg.ECSClusterARNs[i]
		c.datacenter = fmt.Sprintf("dc%d", i)
		c.stateFile = fmt.Sprintf("terraform-%d.tfstate", i)

		t.Run(fmt.Sprintf("secure: %t,enterprise: %t", c.secure, c.enterprise), func(t *testing.T) {
			t.Parallel()

			randomSuffix := strings.ToLower(random.UniqueId())

			tfEnvVars := map[string]string{
				// Use a unique state file for each parallel invocation of Terraform.
				"TF_CLI_ARGS": fmt.Sprintf("-state=%s -state-out=%s", c.stateFile, c.stateFile),
			}

			tfVars := cfg.TFVars("route_table_ids", "ecs_cluster_arns")
			tfVars["secure"] = c.secure
			tfVars["suffix"] = randomSuffix
			tfVars["ecs_cluster_arn"] = c.ecsClusterARN
			tfVars["consul_datacenter"] = c.datacenter
			clientServiceName := "test_client"

			serverServiceName := "test_server"
			if c.secure {
				// This uses the explicitly passed service name rather than the task's family name.
				serverServiceName = "custom_test_server"
			}
			tfVars["server_service_name"] = serverServiceName

			image := discoverConsulImage(t, c.enterprise)
			t.Logf("using consul image = %s", image)
			tfVars["consul_image"] = image
			if c.enterprise {
				license := os.Getenv("CONSUL_LICENSE")
				require.True(t, license != "", "CONSUL_LICENSE not found but is required for enterprise tests")

				// Pass the license via environment variable to help ensure it is not logged.
				tfEnvVars["TF_VAR_consul_license"] = license
			}

			applyOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: initOptions.TerraformDir,
				Vars:         tfVars,
				NoColor:      true,
				EnvVars:      tfEnvVars,
			})

			t.Cleanup(func() {
				if cfg.NoCleanupOnFailure && t.Failed() {
					logger.Log(t, "skipping resource cleanup because -no-cleanup-on-failure=true")
				} else {
					terraform.Destroy(t, applyOptions)
				}
			})

			terraform.Apply(t, applyOptions)

			// Wait for consul server to be up.
			var consulServerTaskARN string
			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
				taskListOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
					Command: "aws",
					Args: []string{
						"ecs",
						"list-tasks",
						"--region",
						cfg.Region,
						"--cluster",
						c.ecsClusterARN,
						"--family",
						fmt.Sprintf("consul_server_%s", randomSuffix),
					},
				})
				r.Check(err)

				var tasks listTasksResponse
				r.Check(json.Unmarshal([]byte(taskListOut), &tasks))
				if len(tasks.TaskARNs) != 1 {
					r.Errorf("expected 1 task, got %d", len(tasks.TaskARNs))
					return
				}

				consulServerTaskARN = tasks.TaskARNs[0]
			})

			// Wait for both tasks to be registered in Consul.
			retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
				out, err := helpers.ExecuteRemoteCommand(t, cfg, c.ecsClusterARN, consulServerTaskARN, "consul-server", `/bin/sh -c "consul catalog services"`)
				r.Check(err)
				if !strings.Contains(out, fmt.Sprintf("%s_%s", serverServiceName, randomSuffix)) ||
					!strings.Contains(out, fmt.Sprintf("%s_%s", clientServiceName, randomSuffix)) {
					r.Errorf("services not yet registered, got %q", out)
				}
			})

			// Wait for passing health check for test_server and test_client
			tokenHeader := ""
			if c.secure {
				tokenHeader = `-H "X-Consul-Token: $CONSUL_HTTP_TOKEN"`
			}

			// Wait for passing health check for `serverServiceName` and `clientServiceName`.
			// `serverServiceName` has a Consul native HTTP check.
			// `clientServiceName`  has a check synced from ECS.
			services := []string{serverServiceName, clientServiceName}
			for _, serviceName := range services {
				retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
					out, err := helpers.ExecuteRemoteCommand(
						t, cfg, c.ecsClusterARN, consulServerTaskARN, "consul-server",
						fmt.Sprintf(`/bin/sh -c 'curl %s localhost:8500/v1/health/checks/%s_%s'`, tokenHeader, serviceName, randomSuffix),
					)
					r.Check(err)

					statusRegex := regexp.MustCompile(`"Status"\s*:\s*"passing"`)
					if statusRegex.FindAllString(out, 1) == nil {
						r.Errorf("Check status not yet passing")
					}
				})
			}

			// Use aws exec to curl between the apps.
			taskListOut := shell.RunCommandAndGetOutput(t, shell.Command{
				Command: "aws",
				Args: []string{
					"ecs",
					"list-tasks",
					"--region",
					cfg.Region,
					"--cluster",
					c.ecsClusterARN,
					"--family",
					fmt.Sprintf("Test_Client_%s", randomSuffix),
				},
			})

			var tasks listTasksResponse
			require.NoError(t, json.Unmarshal([]byte(taskListOut), &tasks))
			require.Len(t, tasks.TaskARNs, 1)
			testClientTaskARN := tasks.TaskARNs[0]
			arnParts := strings.Split(testClientTaskARN, "/")
			testClientTaskID := arnParts[len(arnParts)-1]

			// Create an intention.
			if c.secure {
				// First check that connection between apps is unsuccessful.
				retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
					curlOut, err := helpers.ExecuteRemoteCommand(t, cfg, c.ecsClusterARN, testClientTaskARN, "basic", `/bin/sh -c "curl localhost:1234"`)
					r.Check(err)
					if !strings.Contains(curlOut, `curl: (52) Empty reply from server`) {
						r.Errorf("response was unexpected: %q", curlOut)
					}
				})
				retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
					consulCmd := fmt.Sprintf(`/bin/sh -c "consul intention create %s_%s %s_%s"`, clientServiceName, randomSuffix, serverServiceName, randomSuffix)
					_, err := helpers.ExecuteRemoteCommand(t, cfg, c.ecsClusterARN, consulServerTaskARN, "consul-server", consulCmd)
					r.Check(err)
				})
			}

			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
				curlOut, err := helpers.ExecuteRemoteCommand(t, cfg, c.ecsClusterARN, testClientTaskARN, "basic", `/bin/sh -c "curl localhost:1234"`)
				r.Check(err)
				if !strings.Contains(curlOut, `"code": 200`) {
					r.Errorf("response was unexpected: %q", curlOut)
				}
			})

			// Validate graceful shutdown behavior. We check the client app can reach its upstream after the task is stopped.
			// This relies on a couple of helpers:
			// * a custom entrypoint for the client app that keeps it running for 10s into Task shutdown, and
			// * an additional "shutdown-monitor" container that makes requests to the client app
			// Since this is timing dependent, we check logs after the fact to validate when the containers exited.
			shell.RunCommandAndGetOutput(t, shell.Command{
				Command: "aws",
				Args: []string{
					"ecs",
					"stop-task",
					"--region", cfg.Region,
					"--cluster", c.ecsClusterARN,
					"--task", testClientTaskARN,
					"--reason", "Stopped to validate graceful shutdown in acceptance tests",
				},
			})

			// Wait for the task to stop (~30 seconds)
			retry.RunWith(&retry.Timer{Timeout: 1 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
				describeTasksOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
					Command: "aws",
					Args: []string{
						"ecs",
						"describe-tasks",
						"--region", cfg.Region,
						"--cluster", c.ecsClusterARN,
						"--task", testClientTaskARN,
					},
				})
				r.Check(err)

				var describeTasks ecs.DescribeTasksOutput
				r.Check(json.Unmarshal([]byte(describeTasksOut), &describeTasks))
				require.Len(r, describeTasks.Tasks, 1)
				require.NotEqual(r, "RUNNING", describeTasks.Tasks[0].LastStatus)
			})

			// Check logs to see that the application ignored the TERM signal and exited about 10s later.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				appLogs, err := helpers.GetCloudWatchLogEvents(t, cfg, c.ecsClusterARN, testClientTaskID, "basic")
				require.NoError(r, err)

				logMsg := "consul-ecs: received sigterm. waiting 10s before terminating application."
				appLogs = appLogs.Filter(logMsg)
				require.Len(r, appLogs, 1)
				require.Contains(r, appLogs[0].Message, logMsg)
			})

			// Check that the Envoy entrypoint received the sigterm.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				envoyLogs, err := helpers.GetCloudWatchLogEvents(t, cfg, c.ecsClusterARN, testClientTaskID, "sidecar-proxy")
				require.NoError(r, err)

				logMsg := "consul-ecs: waiting for application container(s) to stop"
				envoyLogs = envoyLogs.Filter(logMsg)
				require.GreaterOrEqual(r, len(envoyLogs), 1)
				require.Contains(r, envoyLogs[0].Message, logMsg)
			})

			// Retrieve "shutdown-monitor" logs to check outgoing requests succeeded.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				monitorLogs, err := helpers.GetCloudWatchLogEvents(t, cfg, c.ecsClusterARN, testClientTaskID, "shutdown-monitor")
				require.NoError(r, err)

				// Check how long after shutdown the upstream was reachable.
				upstreamOkLogs := monitorLogs.Filter(
					"Signal received: signal=terminated",
					"upstream: [OK] GET http://localhost:1234 (200)",
				)
				// The client app is configured to run for about 10 seconds after Task shutdown.
				require.GreaterOrEqual(r, len(upstreamOkLogs.Filter("upstream: [OK]")), 7)
				require.GreaterOrEqual(r, upstreamOkLogs.Duration().Seconds(), 8.0)

				// Double-check the application was still functional for about 10 seconds into Task shutdown.
				// The FakeService makes requests to the upstream, so this further validates Envoy allows outgoing requests.
				applicationOkLogs := monitorLogs.Filter(
					"Signal received: signal=terminated",
					"application: [OK] GET http://localhost:9090 (200)",
				)
				require.GreaterOrEqual(r, len(applicationOkLogs.Filter("application: [OK]")), 7)
				require.GreaterOrEqual(r, applicationOkLogs.Duration().Seconds(), 8.0)
			})

			// Validate that passing additional Consul agent configuration works.
			// We enable DEBUG logs on one of the Consul agents.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				agentLogs, err := helpers.GetCloudWatchLogEvents(t, cfg, c.ecsClusterARN, testClientTaskID, "consul-client")

				require.NoError(r, err)
				logMsg := "[DEBUG] agent:"
				agentLogs = agentLogs.Filter(logMsg)
				require.GreaterOrEqual(r, len(agentLogs), 1)
				require.Contains(r, agentLogs[0].Message, logMsg)
			})

			if c.secure {
				retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
					// Validate that health-sync attempts the 'consul logout' for each of the tokens
					syncLogs, err := helpers.GetCloudWatchLogEvents(t, cfg, c.ecsClusterARN, testClientTaskID, "consul-ecs-health-sync")
					require.NoError(r, err)
					syncLogs = syncLogs.Filter("[INFO]  log out token:")
					require.GreaterOrEqual(r, len(syncLogs), 2)
					require.Contains(r, syncLogs[0].Message, "/consul/service-token")
					require.Contains(r, syncLogs[1].Message, "/consul/client-token")
				})
			}

			logger.Log(t, "Test successful!")
		})
	}
}

// discoverConsulEnterpriseImage looks in mesh-task for the default Consul image
// and uses that same version of the enterprise image.
func discoverConsulImage(t *testing.T, enterprise bool) string {
	filepath := "../../../../modules/mesh-task/variables.tf"
	data, err := os.ReadFile(filepath)
	require.NoError(t, err)

	// Parse the default consul image from the mesh-task module.
	re := regexp.MustCompile(`default\s+=\s+"public.ecr.aws/hashicorp/consul:(.*)"`)
	matches := re.FindSubmatch(data)
	require.Len(t, matches, 2) // entire match + one submatch
	version := string(matches[1])

	if enterprise {
		return "public.ecr.aws/hashicorp/consul-enterprise:" + version + "-ent"
	}
	return "public.ecr.aws/hashicorp/consul:" + version
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}

func TestValidation_AuditLogging(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/audit-logging-validate",
		NoColor:      true,
	})
	_ = terraform.Init(t, terraformOptions)

	cases := map[string]struct {
		auditLogging bool
		acls         bool
		errMsg       string
	}{
		"with audit_logging and acls": {
			auditLogging: true,
			acls:         true,
			errMsg:       "",
		},
		"with audit_logging, without acls": {
			auditLogging: true,
			acls:         false,
			errMsg:       "ERROR: ACLs must be enabled if audit logging is enabled",
		},
	}

	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			terraformOptions.Vars = map[string]interface{}{
				"audit_logging": c.auditLogging,
				"acls":          c.acls,
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
