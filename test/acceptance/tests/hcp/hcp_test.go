package hcp

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	terratestLogger "github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/helpers"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

const setupDir = "../../setup-terraform"

var (
	// Timeout and polling interval for ECS mesh tasks to start and register with Consul.
	registrationTimeout = &retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}
	// Timeout and polling interval for ECS mesh tasks to start reporting healthy status.
	healthTimeout = &retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}
	// Timeout and polling interval for making API calls to the Consul server.
	consulTimeout = &retry.Timer{Timeout: 1 * time.Minute, Wait: 10 * time.Second}
	// Timeout and polling interval for making service calls (curl) between mesh tasks.
	meshTaskTimeout = &retry.Timer{Timeout: 5 * time.Minute, Wait: 20 * time.Second}
)

// retryFunc is a temporary replacement for the retry.RunWith function.
// When using retry.RunWith some non-deterministic failures were observed
// during the acceptance tests.
func retryFunc(rt *retry.Timer, t *testing.T, f func() error) error {
	var err error
	stop := time.Now().Add(rt.Timeout)
	for time.Now().Before(stop) {
		err = f()
		if err == nil {
			return nil
		}
		logger.Log(t, err)
		time.Sleep(rt.Wait)
	}
	return err
}

// HCPTestConfig holds the extended configuration for the admin partition/namespace tests.
type HCPTestConfig struct {
	config.TestConfig
	ECSCluster1ARN          string      `json:"ecs_cluster_1_arn"`
	ECSCluster2ARN          string      `json:"ecs_cluster_2_arn"`
	EnableHCP               bool        `json:"enable_hcp"`
	ConsulAddr              string      `json:"consul_public_endpoint_url"`
	ConsulToken             string      `json:"token"`
	ConsulPrivateAddr       string      `json:"consul_private_endpoint_url"`
	RetryJoin               interface{} `json:"retry_join"`
	BootstrapTokenSecretARN string      `json:"bootstrap_token_secret_arn"`
	GossipKeySecretARN      string      `json:"gossip_key_secret_arn"`
	ConsulCASecretARN       string      `json:"consul_ca_cert_secret_arn"`
}

// parseHCPTestConfig parses terraform outputs from setup-terraform into an HCPTestConfig struct.
// If HCP was not enabled in setup-terraform, it calls t.Skip to skip the test case.
func parseHCPTestConfig(t *testing.T) HCPTestConfig {
	t.Helper()
	// read the configuration from the setup-terraform dir.
	var cfg HCPTestConfig
	require.NoError(t, UnmarshalTF(setupDir, &cfg))

	if !cfg.EnableHCP {
		t.Skip("HCP not enabled. Re-run setup-terraform with enable_hcp=true.")
	}

	return cfg
}

func TestHCP(t *testing.T) {
	cfg := parseHCPTestConfig(t)

	// generate input variables to the test terraform using the config.
	ignoreVars := []string{"ecs_cluster_1_arn", "ecs_cluster_2_arn", "token", "enable_hcp"}
	tfVars := TFVars(cfg, ignoreVars...)

	consulClient, initialConsulState, err := consulClient(t, cfg.ConsulAddr, cfg.ConsulToken)
	require.NoError(t, err)
	t.Cleanup(func() {
		if err := restoreConsulState(t, consulClient, initialConsulState); err != nil {
			logger.Log(t, "failed to restore Consul state:", err)
		}
	})

	randomSuffix := strings.ToLower(random.UniqueId())

	taskConfig := helpers.MeshTaskConfig{
		Partition:    "default",
		Namespace:    "default",
		ConsulClient: consulClient,
		Region:       cfg.Region,
		ClusterARN:   cfg.ECSClusterARN,
	}

	taskConfig.Name = fmt.Sprintf("test_client_%s", randomSuffix)
	clientTask := helpers.NewMeshTask(t, taskConfig)

	taskConfig.Name = fmt.Sprintf("test_server_%s", randomSuffix)
	serverTask := helpers.NewMeshTask(t, taskConfig)

	tfVars["suffix"] = randomSuffix
	terraformOptions, _ := terraformInitAndApply(t, "./terraform/hcp-install", tfVars)
	t.Cleanup(func() { terraformDestroy(t, terraformOptions, suite.Config().NoCleanupOnFailure) })

	// Wait for both tasks to be registered in Consul.
	waitForTasks(t, clientTask, serverTask)

	// Check that the connection between apps is unsuccessful without an intention.
	logger.Log(t, "checking that the connection between apps is unsuccessful without an intention")
	expectCurlOutput(t, clientTask, `curl: (52) Empty reply from server`)

	// Create an intention.
	upsertIntention(t, consulClient, api.IntentionActionAllow, clientTask, serverTask)
	t.Cleanup(func() { deleteIntention(t, consulClient, serverTask) })

	// Now check that the connection succeeds.
	logger.Log(t, "checking that the connection succeeds with an intention")
	expectCurlOutput(t, clientTask, `"code": 200`)

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

// TestNamespaces ensures that services in different namespaces can be
// can be configured to communicate.
func TestNamespaces(t *testing.T) {
	cfg := parseHCPTestConfig(t)

	// generate input variables to the test terraform using the config.
	ignoreVars := []string{"ecs_cluster_1_arn", "ecs_cluster_2_arn", "token", "enable_hcp"}
	tfVars := TFVars(cfg, ignoreVars...)

	consulClient, initialConsulState, err := consulClient(t, cfg.ConsulAddr, cfg.ConsulToken)
	require.NoError(t, err)
	t.Cleanup(func() {
		if err := restoreConsulState(t, consulClient, initialConsulState); err != nil {
			logger.Log(t, "failed to restore Consul state:", err)
		}
	})

	randomSuffix := strings.ToLower(random.UniqueId())

	taskConfig := helpers.MeshTaskConfig{
		ConsulClient: consulClient,
		Region:       cfg.Region,
		ClusterARN:   cfg.ECSClusterARN,
		Partition:    "default",
	}

	taskConfig.Name = fmt.Sprintf("test_client_%s", randomSuffix)
	taskConfig.Namespace = "ns1"
	clientTask := helpers.NewMeshTask(t, taskConfig)

	taskConfig.Name = fmt.Sprintf("test_server_%s", randomSuffix)
	taskConfig.Namespace = "ns2"
	serverTask := helpers.NewMeshTask(t, taskConfig)

	tfVars["suffix"] = randomSuffix
	tfVars["client_namespace"] = clientTask.Namespace
	tfVars["server_namespace"] = serverTask.Namespace

	terraformOptions, _ := terraformInitAndApply(t, "./terraform/ns", tfVars)
	t.Cleanup(func() { terraformDestroy(t, terraformOptions, suite.Config().NoCleanupOnFailure) })

	// Wait for both tasks to be registered in Consul.
	waitForTasks(t, clientTask, serverTask)

	// Check that the connection between apps is unsuccessful without an intention.
	logger.Log(t, "checking that the connection between apps is unsuccessful without an intention")
	expectCurlOutput(t, clientTask, `curl: (52) Empty reply from server`)

	// Create an intention.
	upsertIntention(t, consulClient, api.IntentionActionAllow, clientTask, serverTask)
	t.Cleanup(func() { deleteIntention(t, consulClient, serverTask) })

	// Now check that the connection succeeds.
	logger.Log(t, "checking that the connection succeeds with an intention")
	expectCurlOutput(t, clientTask, `"code": 200`)

	logger.Log(t, "Test successful!")
}

// TestAdminPartitions ensures that services in different admin partitions and namespaces can be
// can be configured to communicate.
func TestAdminPartitions(t *testing.T) {
	cfg := parseHCPTestConfig(t)

	// generate input variables to the test terraform using the config.
	ignoreVars := []string{"ecs_cluster_arn", "token", "enable_hcp"}
	tfVars := TFVars(cfg, ignoreVars...)

	consulClient, initialConsulState, err := consulClient(t, cfg.ConsulAddr, cfg.ConsulToken)
	require.NoError(t, err)
	t.Cleanup(func() {
		if err := restoreConsulState(t, consulClient, initialConsulState); err != nil {
			logger.Log(t, "failed to restore Consul state:", err)
		}
	})

	clientSuffix := strings.ToLower(random.UniqueId())
	serverSuffix := strings.ToLower(random.UniqueId())

	taskConfig := helpers.MeshTaskConfig{
		ConsulClient: consulClient,
		Region:       cfg.Region,
	}

	taskConfig.Name = fmt.Sprintf("test_client_%s", clientSuffix)
	taskConfig.Partition = "part1"
	taskConfig.Namespace = "ns1"
	taskConfig.ClusterARN = cfg.ECSCluster1ARN
	clientTask := helpers.NewMeshTask(t, taskConfig)

	taskConfig.Name = fmt.Sprintf("test_server_%s", serverSuffix)
	taskConfig.Partition = "part2"
	taskConfig.Namespace = "ns2"
	taskConfig.ClusterARN = cfg.ECSCluster2ARN
	serverTask := helpers.NewMeshTask(t, taskConfig)

	tfVars["suffix_1"] = clientSuffix
	tfVars["client_partition"] = clientTask.Partition
	tfVars["client_namespace"] = clientTask.Namespace
	tfVars["suffix_2"] = serverSuffix
	tfVars["server_partition"] = serverTask.Partition
	tfVars["server_namespace"] = serverTask.Namespace

	terraformOptions, _ := terraformInitAndApply(t, "./terraform/ap", tfVars)
	t.Cleanup(func() { terraformDestroy(t, terraformOptions, suite.Config().NoCleanupOnFailure) })

	// Wait for both tasks to be registered in Consul.
	waitForTasks(t, clientTask, serverTask)

	logger.Log(t, "checking that the connection is refused without an `exported-services` config entry")
	expectCurlOutput(t, clientTask, `Connection refused`)

	// Create an exported-services config entry for the server
	upsertExportedServices(t, consulClient, clientTask, serverTask)
	t.Cleanup(func() { deleteExportedServices(t, consulClient, serverTask) })

	logger.Log(t, "checking that the connection between apps is unsuccessful without an intention")
	expectCurlOutput(t, clientTask, `curl: (52) Empty reply from server`)

	// Create an intention.
	logger.Log(t, "upserting intention")
	upsertIntention(t, consulClient, api.IntentionActionAllow, clientTask, serverTask)
	t.Cleanup(func() { deleteIntention(t, consulClient, serverTask) })

	logger.Log(t, "checking that the connection succeeds with an exported-services and intention")
	expectCurlOutput(t, clientTask, `"code": 200`)

	logger.Log(t, "Test successful!")
}

func terraformInitAndApply(t *testing.T, tfDir string, tfVars map[string]interface{}) (*terraform.Options, map[string]interface{}) {
	tfOptions := &terraform.Options{
		TerraformDir: tfDir,
		Vars:         tfVars,
		NoColor:      true,
	}
	terraformOptions := terraform.WithDefaultRetryableErrors(t, tfOptions)

	terraform.InitAndApply(t, terraformOptions)

	outputs := terraform.OutputAll(t, &terraform.Options{
		TerraformDir: tfDir,
		NoColor:      true,
		Logger:       terratestLogger.Discard,
	})
	return terraformOptions, outputs
}

func terraformDestroy(t *testing.T, tfOpts *terraform.Options, noCleanupOnFailure bool) {
	if noCleanupOnFailure && t.Failed() {
		logger.Log(t, "skipping resource cleanup because -no-cleanup-on-failure=true")
	} else {
		terraform.Destroy(t, tfOpts)
	}
}

func waitForTasks(t *testing.T, tasks ...*helpers.MeshTask) {
	// Wait for tasks to register with Consul.
	logger.Log(t, "waiting for services to register with consul")
	require.NoError(t, retryFunc(registrationTimeout, t, func() error {
		for _, task := range tasks {
			if !task.Registered() {
				return fmt.Errorf("%s is not registered", task.Name)
			}
		}
		return nil
	}))

	// Wait for passing health checks for the services.
	logger.Log(t, "waiting for service health checks")
	require.NoError(t, retryFunc(healthTimeout, t, func() error {
		for _, task := range tasks {
			if !task.Healthy() {
				return fmt.Errorf("%s is not healthy", task.Name)
			}
		}
		return nil
	}))
}

func expectCurlOutput(t *testing.T, task *helpers.MeshTask, expected string) {
	require.NoError(t, retryFunc(meshTaskTimeout, t, func() error {
		curlOut, err := task.ExecuteCommand("basic", `/bin/sh -c "curl localhost:1234"`)
		if err != nil {
			return fmt.Errorf("failed to execute command: %w", err)
		}
		if !strings.Contains(curlOut, expected) {
			return fmt.Errorf("unexpected response: %s", curlOut)
		}
		logger.Log(t, "observed expected response:", expected)
		return nil
	}))
}

func upsertIntention(t *testing.T, consulClient *api.Client, action api.IntentionAction, src, dst *helpers.MeshTask) {
	require.NoError(t, retryFunc(consulTimeout, t, func() error {
		_, _, err := consulClient.ConfigEntries().Set(&api.ServiceIntentionsConfigEntry{
			Kind:      api.ServiceIntentions,
			Name:      dst.Name,
			Partition: dst.Partition,
			Namespace: dst.Namespace,
			Sources: []*api.SourceIntention{
				&api.SourceIntention{
					Name:      src.Name,
					Partition: src.Partition,
					Namespace: src.Namespace,
					Action:    action,
				},
			},
		}, dst.WriteOpts())
		if err != nil {
			return fmt.Errorf("failed to upsert intention: %w", err)
		}
		return nil
	}))
}

func deleteIntention(t *testing.T, consulClient *api.Client, dst *helpers.MeshTask) {
	require.NoError(t, retryFunc(consulTimeout, t, func() error {
		_, err := consulClient.ConfigEntries().Delete(api.ServiceIntentions, dst.Name, dst.WriteOpts())
		if err != nil {
			return fmt.Errorf("failed to delete intention: %w", err)
		}
		return nil
	}))
}

func upsertExportedServices(t *testing.T, consulClient *api.Client, src, dst *helpers.MeshTask) {
	require.NoError(t, retryFunc(consulTimeout, t, func() error {
		_, _, err := consulClient.ConfigEntries().Set(&api.ExportedServicesConfigEntry{
			Name:      dst.Partition,
			Partition: dst.Partition,
			Services: []api.ExportedService{{
				Name:      dst.Name,
				Namespace: dst.Namespace,
				Consumers: []api.ServiceConsumer{{Partition: src.Partition}},
			}},
		}, dst.WriteOpts())
		if err != nil {
			return fmt.Errorf("failed to upsert exported-services for %s/%s/%s: %w", dst.Partition, dst.Namespace, dst.Name, err)
		}
		return nil
	}))
}

func deleteExportedServices(t *testing.T, consulClient *api.Client, dst *helpers.MeshTask) {
	require.NoError(t, retryFunc(consulTimeout, t, func() error {
		_, err := consulClient.ConfigEntries().Delete(api.ExportedServices, dst.Partition, dst.WriteOpts())
		if err != nil {
			return fmt.Errorf("failed to delete exported-services for %s: %w", dst.Partition, err)
		}
		return nil
	}))
}

func consulClient(t *testing.T, addr, token string) (*api.Client, ConsulState, error) {
	cfg := api.DefaultConfig()
	cfg.Address = addr
	cfg.Token = token
	client, err := api.NewClient(cfg)
	if err != nil {
		return nil, ConsulState{}, fmt.Errorf("failed to create Consul client: %w", err)
	}
	state, err := recordConsulState(t, client)
	if err != nil {
		return nil, ConsulState{}, fmt.Errorf("failed to establish Consul state: %w", err)
	}
	return client, state, err
}

type ConsulState struct {
	Partitions map[string]PartitionState
}

type PartitionState struct {
	Name       string
	Namespaces map[string]NamespaceState
}

type NamespaceState struct {
	Name        string
	Tokens      map[string]struct{}
	Policies    map[string]struct{}
	Roles       map[string]struct{}
	AuthMethods map[string]struct{}
}

func recordConsulState(t *testing.T, consul *api.Client) (ConsulState, error) {
	// TODO: not sure how to handle OSS vs Enterprise cases.. these tests currently use Enterprise.
	parts, _, err := consul.Partitions().List(context.Background(), nil)
	if err != nil {
		return ConsulState{}, err
	}

	state := ConsulState{Partitions: make(map[string]PartitionState)}
	for _, part := range parts {
		t.Logf("recording partition state for %s", part.Name)
		nss, _, err := consul.Namespaces().List(&api.QueryOptions{Partition: part.Name})
		if err != nil {
			return ConsulState{}, err
		}
		partState := PartitionState{Name: part.Name, Namespaces: make(map[string]NamespaceState)}
		for _, ns := range nss {

			t.Logf("  recording namespace state for %s/%s", part.Name, ns.Name)
			opts := &api.QueryOptions{Partition: part.Name, Namespace: ns.Name}
			nsState := NamespaceState{Name: ns.Name}

			// Tokens
			nsState.Tokens = map[string]struct{}{}
			tokens, _, err := consul.ACL().TokenList(opts)
			if err != nil {
				return ConsulState{}, err
			}
			for _, tok := range tokens {
				t.Logf("    recording token %s in %s/%s", tok.AccessorID, part.Name, ns.Name)
				nsState.Tokens[tok.AccessorID] = struct{}{}
			}

			// Policies
			nsState.Policies = map[string]struct{}{}
			policies, _, err := consul.ACL().PolicyList(opts)
			if err != nil {
				return ConsulState{}, err
			}
			for _, p := range policies {
				t.Logf("    recording policy %s (%s) in %s/%s", p.Name, p.ID, part.Name, ns.Name)
				nsState.Policies[p.ID] = struct{}{}
			}

			// Auth methods
			nsState.AuthMethods = map[string]struct{}{}
			methods, _, err := consul.ACL().AuthMethodList(opts)
			if err != nil {
				return ConsulState{}, err
			}
			for _, method := range methods {
				t.Logf("    recording auth method %s in %s/%s", method.Name, part.Name, ns.Name)
				nsState.AuthMethods[method.Name] = struct{}{}
			}

			partState.Namespaces[ns.Name] = nsState
		}
		state.Partitions[part.Name] = partState
	}
	return state, nil
}

func restoreConsulState(t *testing.T, consul *api.Client, state ConsulState) error {
	parts, _, err := consul.Partitions().List(context.Background(), nil)
	if err != nil {
		return err
	}
	for _, part := range parts {
		partState, existingPart := state.Partitions[part.Name]
		// if the partition is not a pre-existing one, then delete it and continue.
		if !existingPart {
			t.Logf("deleting partition %s", part.Name)
			_, err = consul.Partitions().Delete(context.Background(), part.Name, nil)
			if err != nil {
				return err
			}
			continue
		}

		nss, _, err := consul.Namespaces().List(&api.QueryOptions{Partition: part.Name})
		if err != nil {
			return err
		}
		for _, ns := range nss {
			nsState, existingNS := partState.Namespaces[ns.Name]

			// if the namespace is not a pre-existing one, then delete it and continue.
			if !existingNS {
				t.Logf("  deleting namespace %s/%s", part.Name, ns.Name)
				_, err = consul.Namespaces().Delete(ns.Name, &api.WriteOptions{Partition: part.Name})
				if err != nil {
					return err
				}
				continue
			}

			// if we're here then this is an existing partition/namespace.
			// restore the ACL state.

			qopts := &api.QueryOptions{Partition: part.Name, Namespace: ns.Name}
			wopts := &api.WriteOptions{Partition: part.Name, Namespace: ns.Name}

			// Tokens
			tokens, _, err := consul.ACL().TokenList(qopts)
			if err != nil {
				return err
			}
			for _, tok := range tokens {
				if _, existing := nsState.Tokens[tok.AccessorID]; !existing {
					t.Logf("    deleting token %s from %s/%s", tok.AccessorID, part.Name, ns.Name)
					if _, err = consul.ACL().TokenDelete(tok.AccessorID, wopts); err != nil {
						return err
					}
				}
			}

			// Policies
			policies, _, err := consul.ACL().PolicyList(qopts)
			if err != nil {
				return err
			}
			for _, p := range policies {
				if _, existing := nsState.Policies[p.ID]; !existing {
					t.Logf("    deleting policy %s (%s) from %s/%s", p.Name, p.ID, part.Name, ns.Name)
					if _, err = consul.ACL().PolicyDelete(p.ID, wopts); err != nil {
						return err
					}
				}
			}

			methods, _, err := consul.ACL().AuthMethodList(qopts)
			if err != nil {
				return err
			}
			for _, method := range methods {
				if _, existing := nsState.AuthMethods[method.Name]; !existing {
					t.Logf("    deleting auth method %s from %s/%s", method.Name, part.Name, ns.Name)
					if _, err = consul.ACL().AuthMethodDelete(method.Name, wopts); err != nil {
						return err
					}
				}
			}
		}
	}
	return nil
}

func TestAuditLogging(t *testing.T) {
	cfg := parseHCPTestConfig(t)
	// generate input variables to the test terraform using the config.
	ignoreVars := []string{"ecs_cluster_1_arn", "ecs_cluster_2_arn", "token", "enable_hcp"}
	tfVars := TFVars(cfg, ignoreVars...)

	consulClient, initialConsulState, err := consulClient(t, cfg.ConsulAddr, cfg.ConsulToken)
	require.NoError(t, err)
	t.Cleanup(func() {
		if err := restoreConsulState(t, consulClient, initialConsulState); err != nil {
			logger.Log(t, "failed to restore Consul state:", err)
		}
	})

	randomSuffix := strings.ToLower(random.UniqueId())

	taskConfig := helpers.MeshTaskConfig{
		Partition:    "default",
		Namespace:    "default",
		ConsulClient: consulClient,
		Region:       cfg.Region,
		ClusterARN:   cfg.ECSClusterARN,
	}

	taskConfig.Name = fmt.Sprintf("test_client_%s", randomSuffix)
	clientTask := helpers.NewMeshTask(t, taskConfig)

	taskConfig.Name = fmt.Sprintf("test_server_%s", randomSuffix)
	serverTask := helpers.NewMeshTask(t, taskConfig)

	tfVars["suffix"] = randomSuffix

	// Enable audit logging
	tfVars["audit_logging"] = true

	terraformOptions, _ := terraformInitAndApply(t, "./terraform/hcp-install", tfVars)
	t.Cleanup(func() { terraformDestroy(t, terraformOptions, suite.Config().NoCleanupOnFailure) })

	// Wait for both tasks to be registered in Consul.
	waitForTasks(t, clientTask, serverTask)

	retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
		taskARN, err := clientTask.TaskARN()
		require.NoError(r, err)

		arnParts := strings.Split(taskARN, "/")
		clientTaskID := arnParts[len(arnParts)-1]

		// Get CloudWatch logs and filter to only capture audit logs
		appLogs, err := helpers.GetCloudWatchLogEvents(t, suite.Config(), clientTaskID, "consul-client")
		require.NoError(r, err)
		auditLogs := appLogs.Filter(`"event_type":"audit"`)

		// Check that audit logs were generated else fail
		logger.Log(t, "Number of audit logs generated:", len(auditLogs))
		require.True(r, len(auditLogs) > 0)
	})
	logger.Log(t, "Test successful!")
}
