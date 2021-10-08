package basic

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/consul/sdk/testutil/retry"
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
			// randomSuffix := strings.ToLower(random.UniqueId())
			randomSuffix := "kt4j6f"
			tfVars := suite.Config().TFVars()
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

			t.Log("Wait for consul server to be up.")
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
				t.Logf("consul server task arn = %s", consulServerTaskARN)
			})

			var bootstrapToken string
			if secure {
				t.Logf("Fetching consul client bootstrap token since ACLs are enabled.")
				secretValueOut := shell.RunCommandAndGetOutput(t, shell.Command{
					Command: "aws",
					Args: []string{
						"secretsmanager",
						"get-secret-value",
						"--region", suite.Config().Region,
						"--secret-id", fmt.Sprintf("consul_server_%s-bootstrap-token", randomSuffix),
					},
				})
				var secret map[string]interface{}
				require.NoError(t, json.Unmarshal([]byte(secretValueOut), &secret))
				bootstrapToken = secret["SecretString"].(string)
			}

			consulClient, err := api.NewClient(&api.Config{
				Address: fmt.Sprintf("%s:8500", suite.Config().LbAddress),
				Token:   bootstrapToken,
			})
			require.NoError(t, err)

			t.Log("Wait for tasks to be registered in Consul")
			retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
				services, _, err := consulClient.Catalog().Services(nil)
				t.Logf("consul service catalog: %v", services)
				require.NoError(r, err)
				require.Contains(r, services, fmt.Sprintf("test_client_%s", randomSuffix))
				require.Contains(r, services, fmt.Sprintf("test_server_%s", randomSuffix))
			})

			t.Log("Wait for passing Consul-native health check in test_server")
			retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
				checks, _, err := consulClient.Health().Checks(fmt.Sprintf("test_server_%s", randomSuffix), nil)
				t.Logf("consul checks for test_server:")
				for _, check := range checks {
					t.Logf(" - check: %#v", check)
				}
				require.NoError(r, err)
				require.Len(r, checks, 1)
				require.Equal(r, "server-http", checks[0].CheckID)
				require.Equal(r, api.HealthPassing, checks[0].Status)
			})

			// Setup http client for the test client app
			testClientAddress := fmt.Sprintf("%s:9090", suite.Config().LbAddress)
			client := &http.Client{Timeout: 10 * time.Second}

			// Create an intention.
			if secure {
				// First check that connection between apps is unsuccessful.
				t.Log("Check for unsuccessful connection between apps (due to default deny)")
				retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
					resp, err := httpGetToFakeService(client, testClientAddress)
					require.NoError(r, err)
					t.Logf("GET %s -> %d", testClientAddress, resp.Code)
					require.Equal(r, 500, resp.Code)
					require.Equal(r, -1, resp.UpstreamCalls["http://localhost:1234"].Code)
				})

				t.Log("Create intention to allow traffic from client to server")
				intention := &api.Intention{
					Description:     "Created by acceptance test to allow client app -> server app",
					SourceName:      fmt.Sprintf("test_client_%s", randomSuffix),
					DestinationName: fmt.Sprintf("test_server_%s", randomSuffix),
					Action:          api.IntentionActionAllow,
				}
				_, err := consulClient.Connect().IntentionUpsert(intention, nil)
				require.NoError(t, err)
				t.Logf("created intention: %#v", intention)

				t.Cleanup(func() {
					t.Log("Cleanup intention from client to server")
					_, _ = consulClient.Connect().IntentionDeleteExact(
						fmt.Sprintf("test_client_%s", randomSuffix),
						fmt.Sprintf("test_server_%s", randomSuffix),
						nil,
					)
				})
			}

			t.Log("Check for successful connection between apps")
			retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
				resp, err := httpGetToFakeService(client, testClientAddress)
				require.NoError(r, err)
				t.Logf("GET %s -> %d", testClientAddress, resp.Code)
				require.Equal(r, 200, resp.Code)
				require.Equal(r, 200, resp.UpstreamCalls["http://localhost:1234"].Code)
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

type fakeServiceResponse struct {
	Name          string
	Body          string
	UpstreamCalls map[string]fakeServiceResponse `json:"upstream_calls"`
	Code          int
}

func httpGetToFakeService(client *http.Client, url string) (*fakeServiceResponse, error) {
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}

	respBody, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var fakeResp fakeServiceResponse
	err = json.Unmarshal(respBody, &fakeResp)
	if err != nil {
		return nil, err
	}
	return &fakeResp, nil
}
