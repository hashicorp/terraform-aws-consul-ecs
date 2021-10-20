package basic

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"testing"
	"time"

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

// Test the validation that if ACLs are enabled, Consul client token must also be provided.
func TestValidation_ConsulClientTokenIsRequiredIfACLsIsEnabled(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/consul-client-token-validate",
		NoColor:      true,
	})
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	_, err := terraform.InitAndPlanE(t, terraformOptions)
	require.Error(t, err)
	require.Contains(t, err.Error(), "ERROR: consul_client_token_secret_arn must be set if acls is true")
}

// Test the validation that if ACLs are enabled, ACL secret name prefix must also be provided.
func TestValidation_ACLSecretNamePrefixIsRequiredIfACLsIsEnabled(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/acl-secret-name-prefix-validate",
		NoColor:      true,
	})
	t.Cleanup(func() {
		_, _ = terraform.DestroyE(t, terraformOptions)
	})
	_, err := terraform.InitAndPlanE(t, terraformOptions)
	require.Error(t, err)
	require.Contains(t, err.Error(), "ERROR: acl_secret_name_prefix must be set if acls is true")
}

func TestBasic(t *testing.T) {
	cases := []bool{false, true}

	for _, secure := range cases {
		t.Run(fmt.Sprintf("secure: %t", secure), func(t *testing.T) {
			randomSuffix := strings.ToLower(random.UniqueId())
			tfVars := suite.Config().TFVars("route_table_ids")
			tfVars["secure"] = secure
			tfVars["suffix"] = randomSuffix
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
				if !strings.Contains(out, fmt.Sprintf("test_client_%s", randomSuffix)) ||
					!strings.Contains(out, fmt.Sprintf("test_server_%s", randomSuffix)) {
					r.Errorf("services not yet registered, got %q", out)
				}
			})

			// Wait for passing health check for test_server and test_client
			tokenHeader := ""
			if secure {
				tokenHeader = `-H "X-Consul-Token: $CONSUL_HTTP_TOKEN"`
			}

			// test_server has a Consul native HTTP check
			// test_client has a check synced from ECS
			services := []string{"test_server", "test_client"}
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
					fmt.Sprintf("test_client_%s", randomSuffix),
				},
			})

			var tasks listTasksResponse
			require.NoError(t, json.Unmarshal([]byte(taskListOut), &tasks))
			require.Len(t, tasks.TaskARNs, 1)

			// Create an intention.
			if secure {
				// First check that connection between apps is unsuccessful.
				retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
					curlOut, err := helpers.ExecuteRemoteCommand(t, suite.Config(), tasks.TaskARNs[0], "basic", `/bin/sh -c "curl localhost:1234"`)
					r.Check(err)
					if !strings.Contains(curlOut, `curl: (52) Empty reply from server`) {
						r.Errorf("response was unexpected: %q", curlOut)
					}
				})
				retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
					consulCmd := fmt.Sprintf(`/bin/sh -c "consul intention create test_client_%s test_server_%s"`, randomSuffix, randomSuffix)
					_, err := helpers.ExecuteRemoteCommand(t, suite.Config(), consulServerTaskARN, "consul-server", consulCmd)
					r.Check(err)
				})
			}

			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
				curlOut, err := helpers.ExecuteRemoteCommand(t, suite.Config(), tasks.TaskARNs[0], "basic", `/bin/sh -c "curl localhost:1234"`)
				r.Check(err)
				if !strings.Contains(curlOut, `"code": 200`) {
					r.Errorf("response was unexpected: %q", curlOut)
				}
			})

			// TODO: The token deletion check is disabled due to a race condition.
			// If the service still exists in Consul after a Task stops, the controller skips
			// token deletion. This avoids removing tokens that are still in use, but it means it
			// may never delete a token depending on the timing of consul-client shutting down and
			// the polling interval of the controller.
			//
			// Check that the ACL tokens for services are deleted
			// when services are destroyed.
			//if secure {
			//	// First, destroy just the service mesh services.
			//	tfOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
			//		TerraformDir: "./terraform/basic-install",
			//		Vars:         tfVars,
			//		NoColor:      true,
			//		Targets: []string{
			//			"aws_ecs_service.test_server",
			//			"aws_ecs_service.test_client",
			//			"module.test_server",
			//			"module.test_client",
			//		},
			//	})
			//	terraform.Destroy(t, tfOptions)
			//
			//	// Check that the ACL tokens are deleted from Consul.
			//	retry.RunWith(&retry.Timer{Timeout: 5 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
			//		out, err := executeRemoteCommand(t, consulServerTaskARN, "consul-server", `/bin/sh -c "consul acl token list"`)
			//		require.NoError(r, err)
			//		require.NotContains(r, out, fmt.Sprintf("test_client_%s", randomSuffix))
			//		require.NotContains(r, out, fmt.Sprintf("test_server_%s", randomSuffix))
			//	})
			//}

			logger.Log(t, "Test successful!")
		})
	}
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}
