package hcp

import (
	"fmt"
	"strings"
	"testing"
	"time"

	terratestLogger "github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/helpers"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

func TestHCP(t *testing.T) {
	randomSuffix := strings.ToLower(random.UniqueId())
	tfVars := suite.Config().TFVars()
	tfVars["suffix"] = randomSuffix
	delete(tfVars, "public_subnets")
	tfOptions := &terraform.Options{
		TerraformDir: "./terraform/hcp-install",
		Vars:         tfVars,
		NoColor:      true,
	}
	terraformOptions := terraform.WithDefaultRetryableErrors(t, tfOptions)

	defer func() {
		if suite.Config().NoCleanupOnFailure && t.Failed() {
			logger.Log(t, "skipping resource cleanup because -no-cleanup-on-failure=true")
		} else {
			terraform.Destroy(t, terraformOptions)
		}
	}()
	terraform.InitAndApply(t, terraformOptions)

	outputs := terraform.OutputAll(t, &terraform.Options{
		TerraformDir: "./terraform/hcp-install",
		NoColor:      true,
		Logger:       terratestLogger.Discard,
	})

	cfg := api.DefaultConfig()
	cfg.Address = outputs["hcp_public_endpoint"].(string)
	cfg.Token = outputs["token"].(string)
	consulClient, err := api.NewClient(cfg)
	require.NoError(t, err)

	serverServiceName := fmt.Sprintf("test_server_%s", randomSuffix)
	clientServiceName := fmt.Sprintf("test_client_%s", randomSuffix)

	// Wait for both services to be registered in Consul.
	helpers.WaitForConsulServices(t, consulClient, serverServiceName, clientServiceName)

	// Wait for passing health check for test_server.
	helpers.WaitForConsulHealthChecks(t, consulClient, api.HealthPassing, serverServiceName)

	// Use aws exec to curl between the apps.
	tasks := helpers.ListECSTasks(t, suite.Config(), clientServiceName)
	clientTaskARN := tasks.TaskArns[0]
	require.Len(t, tasks.TaskArns, 1)

	// First check that connection between apps is unsuccessful without an intention.
	helpers.WaitForRemoteCommand(t, suite.Config(), clientTaskARN, "basic",
		`/bin/sh -c "curl localhost:1234"`,
		`curl: (52) Empty reply from server`,
	)

	// Create an intention.
	retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		_, err := consulClient.Connect().IntentionUpsert(&api.Intention{
			SourceName:      clientServiceName,
			DestinationName: serverServiceName,
			Action:          api.IntentionActionAllow,
		}, nil)
		r.Check(err)
	})

	// Now check that the connection succeeds.
	helpers.WaitForRemoteCommand(t, suite.Config(), clientTaskARN, "basic",
		`/bin/sh -c "curl localhost:1234"`,
		`"code": 200`,
	)

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
}
