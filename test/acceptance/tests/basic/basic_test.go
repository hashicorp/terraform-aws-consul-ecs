package basic

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/ecs"
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

func TestPassingExistingRoles(t *testing.T) {
	t.Parallel()
	terraformOptions := &terraform.Options{
		TerraformDir: "./terraform/pass-existing-iam-roles",
		NoColor:      true,
	}
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	terraform.InitAndPlan(t, terraformOptions)
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
		t.Run(name, func(t *testing.T) {
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
		t.Run(name, func(t *testing.T) {
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
		retryJoinWAN            []string
		enableMeshGatewayWANFed bool
		tls                     bool
		expError                string
	}{
		"kind is required": {
			kind:                    "",
			enableMeshGatewayWANFed: false,
			retryJoinWAN:            []string{},
			expError:                `variable "kind" is not set`,
		},
		"kind must be mesh-gateway": {
			kind:                    "not-mesh-gateway",
			enableMeshGatewayWANFed: false,
			retryJoinWAN:            []string{},
			expError:                `Gateway kind must be 'mesh-gateway'`,
		},
		"no WAN federation": {
			kind:                    "mesh-gateway",
			enableMeshGatewayWANFed: false,
			retryJoinWAN:            []string{},
		},
		"mesh gateway WAN federation, no TLS": {
			kind:                    "mesh-gateway",
			enableMeshGatewayWANFed: true,
			tls:                     false,
			retryJoinWAN:            []string{},
			expError:                "tls must be true when enable_mesh_gateway_wan_federation is true",
		},
		"mesh gateway WAN federation": {
			kind:                    "mesh-gateway",
			enableMeshGatewayWANFed: true,
			tls:                     true,
			retryJoinWAN:            []string{},
		},
		"retry join WAN federation": {
			kind:                    "mesh-gateway",
			enableMeshGatewayWANFed: false,
			retryJoinWAN:            []string{"localhost:8500"},
		},
		"error on both": {
			kind:                    "mesh-gateway",
			enableMeshGatewayWANFed: true,
			retryJoinWAN:            []string{"localhost:8500"},
			expError:                "Only one of retry_join_wan or enable_mesh_gateway_wan_federation may be provided",
		},
	}
	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			tfVars := map[string]interface{}{
				"retry_join_wan":                     c.retryJoinWAN,
				"enable_mesh_gateway_wan_federation": c.enableMeshGatewayWANFed,
				"tls":                                c.tls,
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
	cases := []bool{true, false}
	for _, secure := range cases {
		t.Run(fmt.Sprintf("secure: %t", secure), func(t *testing.T) {
			randomSuffix := strings.ToLower(random.UniqueId())
			tfVars := suite.Config().TFVars("route_table_ids")
			tfVars["secure"] = secure
			tfVars["suffix"] = randomSuffix
			clientServiceName := "test_client"

			serverServiceName := "test_server"
			if secure {
				// This uses the explicitly passed service name rather than the task's family name.
				serverServiceName = "custom_test_server"
			}
			tfVars["server_service_name"] = serverServiceName

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: "./terraform/basic-install",
				Vars:         tfVars,
				NoColor:      true,
			})

			t.Cleanup(func() {
				if suite.Config().NoCleanupOnFailure && t.Failed() {
					logger.Log(t, "skipping resource cleanup because -no-cleanup-on-failure=true")
				} else {
					terraform.Destroy(t, terraformOptions)
				}
			})

			terraform.InitAndApply(t, terraformOptions)

			// Wait for consul server to be up.
			var consulServerTaskARN string
			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
				taskListOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
					Command: "aws",
					Args: []string{
						"ecs",
						"list-tasks",
						"--region",
						suite.Config().Region,
						"--cluster",
						suite.Config().ECSClusterARN,
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
				out, err := helpers.ExecuteRemoteCommand(t, suite.Config(), consulServerTaskARN, "consul-server", `/bin/sh -c "consul catalog services"`)
				r.Check(err)
				if !strings.Contains(out, fmt.Sprintf("%s_%s", serverServiceName, randomSuffix)) ||
					!strings.Contains(out, fmt.Sprintf("%s_%s", clientServiceName, randomSuffix)) {
					r.Errorf("services not yet registered, got %q", out)
				}
			})

			// Wait for passing health check for test_server and test_client
			tokenHeader := ""
			if secure {
				tokenHeader = `-H "X-Consul-Token: $CONSUL_HTTP_TOKEN"`
			}

			// Wait for passing health check for `serverServiceName` and `clientServiceName`.
			// `serverServiceName` has a Consul native HTTP check.
			// `clientServiceName`  has a check synced from ECS.
			services := []string{serverServiceName, clientServiceName}
			for _, serviceName := range services {
				retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
					out, err := helpers.ExecuteRemoteCommand(
						t,
						suite.Config(),
						consulServerTaskARN,
						"consul-server",
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
					suite.Config().Region,
					"--cluster",
					suite.Config().ECSClusterARN,
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
			if secure {
				// First check that connection between apps is unsuccessful.
				retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
					curlOut, err := helpers.ExecuteRemoteCommand(t, suite.Config(), testClientTaskARN, "basic", `/bin/sh -c "curl localhost:1234"`)
					r.Check(err)
					if !strings.Contains(curlOut, `curl: (52) Empty reply from server`) {
						r.Errorf("response was unexpected: %q", curlOut)
					}
				})
				retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
					consulCmd := fmt.Sprintf(`/bin/sh -c "consul intention create %s_%s %s_%s"`, clientServiceName, randomSuffix, serverServiceName, randomSuffix)
					_, err := helpers.ExecuteRemoteCommand(t, suite.Config(), consulServerTaskARN, "consul-server", consulCmd)
					r.Check(err)
				})
			}

			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
				curlOut, err := helpers.ExecuteRemoteCommand(t, suite.Config(), testClientTaskARN, "basic", `/bin/sh -c "curl localhost:1234"`)
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
					"--region", suite.Config().Region,
					"--cluster", suite.Config().ECSClusterARN,
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
						"--region", suite.Config().Region,
						"--cluster", suite.Config().ECSClusterARN,
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
				appLogs, err := helpers.GetCloudWatchLogEvents(t, suite.Config(), testClientTaskID, "basic")
				require.NoError(r, err)

				logMsg := "consul-ecs: received sigterm. waiting 10s before terminating application."
				appLogs = appLogs.Filter(logMsg)
				require.Len(r, appLogs, 1)
				require.Contains(r, appLogs[0].Message, logMsg)
			})

			// Check that the Envoy entrypoint received the sigterm.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				envoyLogs, err := helpers.GetCloudWatchLogEvents(t, suite.Config(), testClientTaskID, "sidecar-proxy")
				require.NoError(r, err)

				logMsg := "consul-ecs: waiting for application container(s) to stop"
				envoyLogs = envoyLogs.Filter(logMsg)
				require.GreaterOrEqual(r, len(envoyLogs), 1)
				require.Contains(r, envoyLogs[0].Message, logMsg)
			})

			// Retrieve "shutdown-monitor" logs to check outgoing requests succeeded.
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
				monitorLogs, err := helpers.GetCloudWatchLogEvents(t, suite.Config(), testClientTaskID, "shutdown-monitor")
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
				agentLogs, err := helpers.GetCloudWatchLogEvents(t, suite.Config(), testClientTaskID, "consul-client")

				require.NoError(r, err)
				logMsg := "[DEBUG] agent:"
				agentLogs = agentLogs.Filter(logMsg)
				require.GreaterOrEqual(r, len(agentLogs), 1)
				require.Contains(r, agentLogs[0].Message, logMsg)
			})

			if secure {
				retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
					// Validate that health-sync attempts the 'consul logout' for each of the tokens
					syncLogs, err := helpers.GetCloudWatchLogEvents(t, suite.Config(), testClientTaskID, "consul-ecs-health-sync")
					require.NoError(r, err)
					syncLogs = syncLogs.Filter("[INFO]  log out token:")
					require.Contains(r, syncLogs[0].Message, "/consul/service-token")
					require.Contains(r, syncLogs[1].Message, "/consul/client-token")
				})
			}

			logger.Log(t, "Test successful!")
		})
	}
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}
