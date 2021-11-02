package basic

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/api"
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
	randomSuffix := strings.ToLower(random.UniqueId())
	serverServiceName := fmt.Sprintf("custom_test_server_%s", randomSuffix)
	clientServiceName := fmt.Sprintf("test_client_%s", randomSuffix)

	tfVars := suite.Config().TFVars("route_table_ids")
	tfVars["suffix"] = randomSuffix
	// This uses the explicitly passed service name rather than the task's family name.
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

	outputs := terraform.OutputAll(t, terraformOptions)

	// Create a consul client.
	cfg := api.DefaultConfig()
	cfg.Address = outputs["consul_server_url"].(string)
	consulClient, err := api.NewClient(cfg)
	require.NoError(t, err)

	// Wait for both tasks to be registered in Consul.
	helpers.WaitForConsulServices(t, consulClient, serverServiceName, clientServiceName)

	// Wait for passing health check for `serverServiceName` and `clientServiceName`.
	// `serverServiceName` has a Consul native HTTP check.
	// `clientServiceName`  has a check synced from ECS.
	helpers.WaitForConsulHealthChecks(t, consulClient, api.HealthPassing, serverServiceName, clientServiceName)

	// Use aws exec to curl between the apps.
	tasks := helpers.ListECSTasks(t, suite.Config(), clientServiceName)
	require.Len(t, tasks.TaskArns, 1)
	clientTaskARN := tasks.TaskArns[0]
	arnParts := strings.Split(clientTaskARN, "/")
	clientTaskId := arnParts[len(arnParts)-1]

	helpers.WaitForRemoteCommand(t, suite.Config(), clientTaskARN, "basic",
		`/bin/sh -c "curl localhost:1234"`,
		`"code": 200`,
	)

	// Validate graceful shutdown behavior. We check the client app can reach its upstream after the task is stopped.
	// This relies on a couple of helpers:
	// * a custom entrypoint for the client app that keeps it running for 10s into Task shutdown, and
	// * an additional "shutdown-monitor" container that makes requests to the client app
	// Since this is timing dependent, we check logs after the fact to validate when the containers exited.
	helpers.StopECSTask(t, suite.Config(), clientTaskARN)
	helpers.WaitForECSTask(t, suite.Config(), "STOPPED", clientTaskARN)

	// Check logs to see that the application ignored the TERM signal and exited about 10s later.
	helpers.WaitForLogEvents(t, suite.Config(), clientTaskId, "basic",
		map[string]int{
			"TEST LOG: Caught sigterm. Sleeping 10s...": 1,
			"TEST LOG: on exit":                         1,
		},
		9*time.Second,
	)

	// Check that Envoy ignored the sigterm.
	helpers.WaitForLogEvents(t, suite.Config(), clientTaskId, "sidecar-proxy",
		map[string]int{
			"consul-ecs: waiting for application container(s) to stop": 1,
		},
		0*time.Second,
	)

	// Retrieve "shutdown-monitor" logs to check outgoing requests succeeded.
	helpers.WaitForLogEvents(t, suite.Config(), clientTaskId, "shutdown-monitor",
		map[string]int{
			"Signal received: signal=terminated":                1,
			"upstream: [OK] GET http://localhost:1234 (200)":    7,
			"application: [OK] GET http://localhost:9090 (200)": 7,
		},
		8*time.Second,
	)

	logger.Log(t, "Test successful!")
}
