package suite

import (
	"flag"
	"fmt"
	"os/exec"
	"testing"

	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/flags"
)

// DefaultExecs holds the default external executables that are required to
// run the tests. They can be overridden or customized per test as needed.
var DefaultExecs = []string{
	"aws",
	"ecs-cli",
	"session-manager-plugin",
	"terraform",
}

type suite struct {
	m     *testing.M
	cfg   *config.TestConfig
	flags *flags.TestFlags
	execs []string
}

type Suite interface {
	Run() int
	Config() *config.TestConfig
}

func NewSuite(m *testing.M, execs ...string) Suite {
	flags := flags.NewTestFlags()

	flag.Parse()

	exes := DefaultExecs
	if len(execs) > 0 {
		exes = execs
	}

	return &suite{
		m:     m,
		flags: flags,
		execs: exes,
	}
}

func (s *suite) Run() int {
	err := s.Vet()
	if err != nil {
		fmt.Printf("Failed to run tests: %s\n", err)
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

// Vet ensures that the test suite is in a state that it can run.
// It returns a non-nil error if there are failures.
func (s *suite) Vet() error {
	// validate flags
	if err := s.flags.Validate(); err != nil {
		return fmt.Errorf("flag validation failed: %s", err)
	}

	// check for required execs
	var missing string
	for _, e := range s.execs {
		if _, err := exec.LookPath(e); err != nil {
			missing += ", " + e
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("missing required executable(s) from PATH: %s", missing[2:])
	}
	return nil
}
