package helpers

import (
	"testing"
	"time"

	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

// WaitForConsulServices waits for services to show in the consul service catalog.
func WaitForConsulServices(t *testing.T, consulClient *api.Client, serviceNames ...string) {
	logger.Logf(t, "waiting for services to be registered, services=%v", serviceNames)
	retry.RunWith(&retry.Timer{Timeout: 6 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		services, _, err := consulClient.Catalog().Services(nil)
		r.Check(err)
		logger.Logf(t, "Consul services: %v", services)
		for _, service := range serviceNames {
			require.Contains(r, services, service)
		}
	})
}

// WaitForConsulHealthChecks waits for all health checks for each service to match the status.
// It requires at least one check for each service.
func WaitForConsulHealthChecks(t *testing.T, consulClient *api.Client, status string, serviceNames ...string) {
	logger.Logf(t, "waiting for %s health checks, services=%v", status, serviceNames)
	retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 20 * time.Second}, t, func(r *retry.R) {
		for _, service := range serviceNames {
			checks, _, err := consulClient.Health().Checks(service, nil)
			r.Check(err)
			t.Logf("%s health checks:", service)
			for _, check := range checks {
				t.Logf("%#v", *check)
			}
			require.GreaterOrEqual(r, len(checks), 1)
			for _, check := range checks {
				require.Equal(r, status, check.Status)
			}
		}
	})
}
