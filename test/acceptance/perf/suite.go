package perf

import (
	"flag"
	"fmt"
	"sync"
	"testing"
)

const (
	flagNoCleanup                      = "no-cleanup"
	flagDatadogAPIKey                  = "datadog-api-key"
	flagServiceGroups                  = "service-groups"
	flagServerInstancesPerServiceGroup = "server-instances-per-service-group"
	flagPercentRestart                 = "percent-restart"
	flagLBIngressIP                    = "lb-ingress-ip"
	flagRestarts                       = "restarts"
)

// TestConfig holds configuration for the test suite.
type TestConfig struct {
	NoCleanup                      bool
	DatadogAPIKey                  string
	ServiceGroups                  int
	ServerInstancesPerServiceGroup int
	PercentRestart                 int
	LBIngressIP                    string
	Restarts                       int
}

func (t TestConfig) TFVars() map[string]interface{} {
	vars := map[string]interface{}{
		"service_groups":                     t.ServiceGroups,
		"server_instances_per_service_group": t.ServerInstancesPerServiceGroup,
		"datadog_api_key":                    t.DatadogAPIKey,
		"lb_ingress_ip":                      t.LBIngressIP,
	}

	return vars
}

type TestFlags struct {
	flagNoCleanup                      bool
	flagDatadogAPIKey                  string
	flagServiceGroups                  int
	flagPercentRestart                 int
	flagRestarts                       int
	flagServerInstancesPerServiceGroup int
	flagLBIngressIP                    string

	once sync.Once
}

func NewTestFlags() *TestFlags {
	t := &TestFlags{}
	t.once.Do(t.init)

	return t
}

func (t *TestFlags) init() {
	flag.BoolVar(&t.flagNoCleanup, flagNoCleanup, false,
		"If true, the tests will not clean up resources they create when they finish running.")
	flag.StringVar(&t.flagDatadogAPIKey, flagDatadogAPIKey, "", "The Datadog API key")
	flag.IntVar(&t.flagServiceGroups, flagServiceGroups, 0,
		"The total number of service groups")
	flag.IntVar(&t.flagServerInstancesPerServiceGroup, flagServerInstancesPerServiceGroup, 0,
		"Number of server instances per service group")
	flag.IntVar(&t.flagPercentRestart, flagPercentRestart, 0,
		"Percent of the tasks to kill")
	flag.IntVar(&t.flagRestarts, flagRestarts, 1,
		"Number of times to kill tasks")
	flag.StringVar(&t.flagLBIngressIP, flagLBIngressIP, "",
		"The IP address that will access the Consul UI")
}

func (t *TestFlags) Validate() error {
	if t.flagDatadogAPIKey == "" {
		return fmt.Errorf("%q is required", flagDatadogAPIKey)
	}

	if t.flagServiceGroups == 0 {
		return fmt.Errorf("%q is required", flagServiceGroups)
	}

	if t.flagPercentRestart == 0 {
		return fmt.Errorf("%q is required", flagPercentRestart)
	}

	if t.flagLBIngressIP == "" {
		return fmt.Errorf("%q is required", flagLBIngressIP)
	}

	return nil
}

func (t *TestFlags) TestConfigFromFlags() *TestConfig {
	cfg := TestConfig{
		NoCleanup:                      t.flagNoCleanup,
		DatadogAPIKey:                  t.flagDatadogAPIKey,
		ServiceGroups:                  t.flagServiceGroups,
		ServerInstancesPerServiceGroup: t.flagServerInstancesPerServiceGroup,
		PercentRestart:                 t.flagPercentRestart,
		Restarts:                       t.flagRestarts,
		LBIngressIP:                    t.flagLBIngressIP,
	}

	return &cfg
}

type suite struct {
	m     *testing.M
	cfg   *TestConfig
	flags *TestFlags
}

type Suite interface {
	Run() int
	Config() *TestConfig
}

func NewSuite(m *testing.M) Suite {
	flags := NewTestFlags()

	flag.Parse()

	return &suite{
		m:     m,
		flags: flags,
	}
}

func (s *suite) Run() int {
	err := s.flags.Validate()
	if err != nil {
		fmt.Printf("Flag validation failed: %s\n", err)
		return 1
	}

	testConfig := s.flags.TestConfigFromFlags()
	s.cfg = testConfig

	return s.m.Run()
}

func (s *suite) Config() *TestConfig {
	return s.cfg
}
