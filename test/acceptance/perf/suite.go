package perf

import (
	"flag"
	"fmt"
	"sync"
	"testing"

	"github.com/hashicorp/hcl/v2/hclsimple"
)

const (
	flagConfigPath = "config-path"
	flagRestarts   = "restarts"
)

type Config struct {
	ConsulLicense                  string `hcl:"consul_license"`
	DatadogAPIKey                  string `hcl:"datadog_api_key"`
	LBIngressIP                    string `hcl:"lb_ingress_ip"`
	ServiceGroups                  int    `hcl:"desired_service_groups"`
	ServerInstancesPerServiceGroup int    `hcl:"server_instances_per_group"`
	ClientInstancesPerServiceGroup int    `hcl:"client_instances_per_group"`
}

// TestConfig holds configuration for the test suite.
type TestConfig struct {
	ConfigPath                     string
	Restarts                       int
	ServiceGroups                  int
	ServerInstancesPerServiceGroup int
	ClientInstancesPerServiceGroup int
}

type TestFlags struct {
	flagConfigPath string
	flagRestarts   int

	once sync.Once
}

func NewTestFlags() *TestFlags {
	t := &TestFlags{}
	t.once.Do(t.init)

	return t
}

func (t *TestFlags) init() {
	flag.StringVar(&t.flagConfigPath, flagConfigPath, "",
		"The location of the terraform input vars file")
	flag.IntVar(&t.flagRestarts, flagRestarts, 1,
		"Number of times to kill tasks within a service group")
}

func (t *TestFlags) Validate() error {
	if t.flagConfigPath == "" {
		return fmt.Errorf("%q is required", flagConfigPath)
	}

	return nil
}

func (t *TestFlags) TestConfigFromFlags() (*TestConfig, error) {
	var testConfig TestConfig
	var config Config
	err := hclsimple.DecodeFile(t.flagConfigPath, nil, &config)
	if err != nil {
		return &testConfig, fmt.Errorf("failed to load configuration: %s", err)
	}

	testConfig = TestConfig{
		Restarts:                       t.flagRestarts,
		ConfigPath:                     t.flagConfigPath,
		ServiceGroups:                  config.ServiceGroups,
		ClientInstancesPerServiceGroup: config.ClientInstancesPerServiceGroup,
		ServerInstancesPerServiceGroup: config.ServerInstancesPerServiceGroup,
	}

	return &testConfig, nil
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

	testConfig, err := s.flags.TestConfigFromFlags()
	if err != nil {
		fmt.Printf("Constructing configuration failed: %s\n", err)
		return 1
	}

	s.cfg = testConfig

	return s.m.Run()
}

func (s *suite) Config() *TestConfig {
	return s.cfg
}
