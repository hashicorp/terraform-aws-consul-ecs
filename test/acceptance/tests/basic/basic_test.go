package basic

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	terratestLogger "github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
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

func TestFargate(t *testing.T) {
	t.Parallel()

	cases := []bool{false, true}
	for _, secure := range cases {
		t.Run(fmt.Sprintf("secure: %t", secure), func(t *testing.T) {
			doBasicInstall(t, secure, "FARGATE")
		})
	}
}

func TestEC2(t *testing.T) {
	t.Parallel()

	cases := []bool{false, true}
	for _, secure := range cases {
		t.Run(fmt.Sprintf("secure: %t", secure), func(t *testing.T) {
			doBasicInstall(t, secure, "EC2")
		})
	}
}

// Helper to deploy the `basic-install` Terraform module, which will
// deploy a sample client-server application in an ECS cluster.
func doBasicInstall(t *testing.T, secure bool, launchType string) {
	// Use separate clusters for FARGATE / EC2 to run in parallel.
	var clusterArn string
	if launchType == "FARGATE" {
		clusterArn = suite.Config().ECSClusterARN_Fargate
	} else if launchType == "EC2" {
		clusterArn = suite.Config().ECSClusterARN_EC2
	} else {
		t.Fatalf("invalid launch type: %s", launchType)
	}
	if clusterArn == "" {
		t.Fatalf("no cluster ARN for %s launch type", launchType)
	}

	randomSuffix := strings.ToLower(random.UniqueId())
	tfVars := suite.Config().TFVars()
	tfVars["secure"] = secure
	tfVars["suffix"] = randomSuffix
	tfVars["launch_type"] = launchType
	tfVars["ecs_cluster_arn"] = clusterArn

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./terraform/basic-install",
		Vars:         tfVars,
		NoColor:      true,
		EnvVars:      map[string]string{},
	})
	terraform.Init(t, terraformOptions)

	// Unique-ify state files by launch type since we parallelize by launch type.
	// This means only two state files to deal with in case of manual cleanup locally.
	stateFile := fmt.Sprintf("terraform-%s.tfstate", launchType)

	// `terraform init` doesn't accept the `-state` option, so add it here for the apply/destroy.
	// The `-state-out` option affects the backup file location.
	terraformOptions.EnvVars["TF_CLI_ARGS"] = fmt.Sprintf("-state=%s -state-out=%s", stateFile, stateFile)

	defer func() {
		if suite.Config().NoCleanupOnFailure && t.Failed() {
			logger.Log(t, "skipping resource cleanup because -no-cleanup-on-failure=true")
		} else {
			terraform.Destroy(t, terraformOptions)
		}
	}()
	terraform.Apply(t, terraformOptions)

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
				clusterArn,
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
		out, err := shell.RunCommandAndGetOutputE(t, shell.Command{
			Command: "aws",
			Args: []string{
				"ecs",
				"execute-command",
				"--region",
				suite.Config().Region,
				"--cluster",
				clusterArn,
				"--task",
				consulServerTaskARN,
				"--container=consul-server",
				"--command",
				`/bin/sh -c "consul catalog services"`,
				"--interactive",
			},
			Logger: terratestLogger.New(logger.TestLogger{}),
		})
		r.Check(err)
		if !strings.Contains(out, fmt.Sprintf("test_client_%s", randomSuffix)) ||
			!strings.Contains(out, fmt.Sprintf("test_server_%s", randomSuffix)) {
			r.Errorf("services not yet registered, got %q", out)
		}
	})

	// Use aws exec to curl between the apps.
	taskListOut := shell.RunCommandAndGetOutput(t, shell.Command{
		Command: "aws",
		Args: []string{
			"ecs",
			"list-tasks",
			"--region",
			suite.Config().Region,
			"--cluster",
			clusterArn,
			"--family",
			fmt.Sprintf("test_client_%s", randomSuffix),
		},
	})

	var tasks listTasksResponse
	require.NoError(t, json.Unmarshal([]byte(taskListOut), &tasks))
	require.Len(t, tasks.TaskARNs, 1)

	// Create an intention.
	if secure {
		// First check that connection between apps in unsuccessful.
		retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
			curlOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
				Command: "aws",
				Args: []string{
					"ecs",
					"execute-command",
					"--region",
					suite.Config().Region,
					"--cluster",
					clusterArn,
					"--task",
					tasks.TaskARNs[0],
					"--container=basic",
					"--command",
					`/bin/sh -c "curl localhost:1234"`,
					"--interactive",
				},
				Logger: terratestLogger.New(logger.TestLogger{}),
			})
			r.Check(err)
			if !strings.Contains(curlOut, `curl: (52) Empty reply from server`) {
				r.Errorf("response was unexpected: %q", curlOut)
			}
		})
		retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
			_, err := shell.RunCommandAndGetOutputE(t, shell.Command{
				Command: "aws",
				Args: []string{
					"ecs",
					"execute-command",
					"--region",
					suite.Config().Region,
					"--cluster",
					clusterArn,
					"--task",
					consulServerTaskARN,
					"--container=consul-server",
					"--command",
					fmt.Sprintf(`/bin/sh -c "consul intention create test_client_%s test_server_%s"`, randomSuffix, randomSuffix),
					"--interactive",
				},
				Logger: terratestLogger.New(logger.TestLogger{}),
			})
			r.Check(err)
		})
	}

	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		curlOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{
			Command: "aws",
			Args: []string{
				"ecs",
				"execute-command",
				"--region",
				suite.Config().Region,
				"--cluster",
				clusterArn,
				"--task",
				tasks.TaskARNs[0],
				"--container=basic",
				"--command",
				`/bin/sh -c "curl localhost:1234"`,
				"--interactive",
			},
			Logger: terratestLogger.New(logger.TestLogger{}),
		})
		r.Check(err)
		if !strings.Contains(curlOut, `"code": 200`) {
			r.Errorf("response was unexpected: %q", curlOut)
		}
	})

	logger.Log(t, "Test successful!")
}

type listTasksResponse struct {
	TaskARNs []string `json:"taskArns"`
}
