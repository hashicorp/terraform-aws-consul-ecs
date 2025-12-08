// Copyright IBM Corp. 2021, 2025
// SPDX-License-Identifier: MPL-2.0

package common

import (
	"fmt"
	"testing"
	"time"

	"github.com/hashicorp/consul/api"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/logger"
	"github.com/stretchr/testify/require"
)

type ConsulClientWrapper struct {
	t      *testing.T
	client *api.Client
}

type ClientOpts func(*api.Config)

// SetupConsulClient sets up a consul client that can be used to directly
// interact with the consul server.
func SetupConsulClient(t *testing.T, serverAddr string, opts ...ClientOpts) (*ConsulClientWrapper, error) {
	cfg := api.DefaultConfig()
	cfg.Address = serverAddr

	for _, opt := range opts {
		opt(cfg)
	}

	client, err := api.NewClient(cfg)
	if err != nil {
		return nil, err
	}
	return &ConsulClientWrapper{
		t:      t,
		client: client,
	}, nil
}

func WithToken(token string) ClientOpts {
	return func(c *api.Config) {
		c.Token = token
	}
}

// EnsureServiceReadiness makes sure that a service with a given name
// is registered as part of Consul's catalog and is also healthy.
func (ccw *ConsulClientWrapper) EnsureServiceReadiness(name string, queryOpts *api.QueryOptions) {
	ccw.ensureServiceRegistration(name, queryOpts)
	ccw.ensureHealthyService(name, queryOpts)
}

// EnsureServiceDeregistration makes sure that a service with a given name
// is registered as part of Consul's catalog
func (ccw *ConsulClientWrapper) EnsureServiceDeregistration(name string, queryOpts *api.QueryOptions) {
	logger.Log(ccw.t, fmt.Sprintf("checking if service %s is deregistered from Consul", name))
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, ccw.t, func(r *retry.R) {
		exists, err := ccw.serviceExists(name, queryOpts)
		require.NoError(r, err)
		require.False(r, exists)
	})
}

// EnsureServiceInstances verifies if the number of service instances for a service
// in Consul catalog matches the expected count.
func (ccw *ConsulClientWrapper) EnsureServiceInstances(name string, expectedCount int, queryOpts *api.QueryOptions) {
	logger.Log(ccw.t, fmt.Sprintf("checking if service %s has two instances registered", name))
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, ccw.t, func(r *retry.R) {
		instances, err := ccw.listServiceInstances(name, nil)
		require.NoError(r, err)
		require.Len(r, instances, expectedCount)
	})
}

// ensureServiceRegistration makes sure that a service with a given name
// is registered as part of Consul's catalog
func (ccw *ConsulClientWrapper) ensureServiceRegistration(name string, queryOpts *api.QueryOptions) {
	logger.Log(ccw.t, fmt.Sprintf("checking if service %s is registered in Consul", name))
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, ccw.t, func(r *retry.R) {
		exists, err := ccw.serviceExists(name, queryOpts)
		require.NoError(r, err)
		require.True(r, exists)
	})
}

// ensureHealthyService polls the catalog endpoint to understand a service's health status.
// Note that the health of a service is an accumulation of all the health checks associated
// with that of the service instances of that service.
func (ccw *ConsulClientWrapper) ensureHealthyService(name string, opts *api.QueryOptions) {
	logger.Log(ccw.t, fmt.Sprintf("checking if all instances of %s are healthy", name))
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, ccw.t, func(r *retry.R) {
		healthy, err := ccw.isServiceHealthy(name, opts)
		require.NoError(r, err)
		require.True(r, healthy)
	})
}

// serviceExists verifies if a service with a given name exists in Consul's catalog.
func (ccw *ConsulClientWrapper) serviceExists(serviceName string, queryOpts *api.QueryOptions) (bool, error) {
	services, err := ccw.listServices(queryOpts)
	if err != nil {
		return false, err
	}

	_, ok := services[serviceName]
	return ok, nil
}

// isServiceHealthy verifies if all service instances of a service with a given name are healthy in Consul's catalog.
func (ccw *ConsulClientWrapper) isServiceHealthy(serviceName string, queryOpts *api.QueryOptions) (bool, error) {
	res, _, err := ccw.client.Health().Checks(serviceName, queryOpts)
	if err != nil {
		return false, err
	}

	return res.AggregatedStatus() == api.HealthPassing, nil
}

// ListServiceInstances returns the list of service instances for a given service
func (c *ConsulClientWrapper) listServiceInstances(serviceName string, queryOpts *api.QueryOptions) ([]*api.CatalogService, error) {
	instances, _, err := c.client.Catalog().Service(serviceName, "", queryOpts)
	if err != nil {
		return nil, err
	}

	return instances, nil
}

func (c *ConsulClientWrapper) listServices(opts *api.QueryOptions) (map[string][]string, error) {
	services, _, err := c.client.Catalog().Services(opts)
	if err != nil {
		return nil, err
	}

	return services, nil
}
