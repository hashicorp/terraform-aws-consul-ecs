package suite

import (
	"flag"
	"fmt"
	"testing"

	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/flags"
)

type suite struct {
	m     *testing.M
	cfg   *config.TestConfig
	flags *flags.TestFlags
}

type Suite interface {
	Run() int
	Config() *config.TestConfig
}

func NewSuite(m *testing.M) Suite {
	flags := flags.NewTestFlags()

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
		fmt.Printf("Failed to create test config: %s\n", err)
		return 1
	}
	s.cfg = testConfig

	return s.m.Run()
}

func (s *suite) Config() *config.TestConfig {
	return s.cfg
}
