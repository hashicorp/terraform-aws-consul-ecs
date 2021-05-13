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

	testConfig := flags.TestConfigFromFlags()

	return &suite{
		m:     m,
		cfg:   testConfig,
		flags: flags,
	}
}

func (s *suite) Run() int {
	err := s.flags.Validate()
	if err != nil {
		fmt.Printf("Flag validation failed: %s\n", err)
		return 1
	}

	return s.m.Run()
}

func (s *suite) Config() *config.TestConfig {
	return s.cfg
}
