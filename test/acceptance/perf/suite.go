package perf

import (
	"flag"
	"fmt"
	"sync"
	"testing"

	"github.com/hashicorp/hcl/v2/hclsimple"
)

const (
	flagConfigPath      = "config-path"
	flagRestarts        = "restarts"
	flagMode            = "mode"
	flagOutputCSVPath   = "output-csv-path"
	flagPercentRestart  = "percent-restart"
	flagStableThreshold = "stable-threshold"
)

type Config struct {
	SericeGroups                   int    `hcl:"service_groups"`
	ServerInstancesPerServiceGroup int    `hcl:"server_instances_per_service_group"`
	ClientInstancesPerServiceGroup int    `hcl:"client_instances_per_service_group"`
	LBIngressIP                    string `hcl:"lb_ingress_ip"`
	DatadogAPIKey                  string `hcl:"datadog_api_key"`
	ConsulVersion                  string `hcl:"consul_version"`
}

// TestConfig holds configuration for the test suite.
type TestConfig struct {
	ConfigPath                     string
	Restarts                       int
	PercentRestart                 int
	Mode                           string
	OutputCSVPath                  string
	ServiceGroups                  int
	ServerInstancesPerServiceGroup int
	ClientInstancesPerServiceGroup int
	StableThreshold                int
}

type TestFlags struct {
	flagPercentRestart  int
	flagRestarts        int
	flagMode            string
	flagOutputCSVPath   string
	flagConfigPath      string
	flagStableThreshold int

	once sync.Once
}

func NewTestFlags() *TestFlags {
	t := &TestFlags{}
	t.once.Do(t.init)

	return t
}

func (t *TestFlags) init() {
	flag.StringVar(&t.flagConfigPath, flagConfigPath, "",
		"The location of the terraform config")
	flag.IntVar(&t.flagPercentRestart, flagPercentRestart, 0,
		"Percent of the tasks to kill")
	flag.IntVar(&t.flagRestarts, flagRestarts, 1,
		"Number of times to kill tasks")
	flag.StringVar(&t.flagMode, flagMode, "everything",
		"The mode the tests will run in. Either 'everything' or 'service-group'")

	flag.StringVar(&t.flagOutputCSVPath, flagOutputCSVPath, "",
		"The path to write service group stabilization times to")

	flag.IntVar(&t.flagStableThreshold, flagStableThreshold, 100,
		"The percent of stable service groups before killing tasks.")
}

func (t *TestFlags) Validate() error {
	if t.flagPercentRestart == 0 {
		return fmt.Errorf("%q is required", flagPercentRestart)
	}

	if t.flagConfigPath == "" {
		return fmt.Errorf("%q is required", flagConfigPath)
	}

	if t.flagStableThreshold < 0 || t.flagStableThreshold > 100 {
		return fmt.Errorf("%q must be between 0 and 100", flagStableThreshold)
	}

	if t.flagMode != "everything" && t.flagMode != "service-group" {
		return fmt.Errorf("%q needs to be 'everything' or 'service-group'", flagMode)
	}

	return nil
}

func (t *TestFlags) TestConfigFromFlags() (*TestConfig, error) {
	var testConfig TestConfig
	var config Config
	err := hclsimple.DecodeFile(t.flagConfigPath, nil, &config)
	if err != nil {
		return &testConfig, fmt.Errorf("Failed to load configuration: %s", err)
	}

	testConfig = TestConfig{
		PercentRestart:                 t.flagPercentRestart,
		Restarts:                       t.flagRestarts,
		Mode:                           t.flagMode,
		OutputCSVPath:                  t.flagOutputCSVPath,
		ConfigPath:                     t.flagConfigPath,
		ServiceGroups:                  config.SericeGroups,
		ClientInstancesPerServiceGroup: config.ClientInstancesPerServiceGroup,
		ServerInstancesPerServiceGroup: config.ServerInstancesPerServiceGroup,
		StableThreshold:                t.flagStableThreshold,
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
