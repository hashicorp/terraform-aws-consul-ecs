// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package common

import (
	"io"
	"net/http"

	"github.com/hashicorp/consul/api"
)

// This method relies on a third party API to retrieve
// the public IP of the host where this test runs.
func GetPublicIP() (string, error) {
	resp, err := http.Get("https://api64.ipify.org?format=text")
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	ip, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	return string(ip), nil
}

// SetupConsulClient sets up a consul client that can be used to directly
// interact with the consul server.
func SetupConsulClient(serverAddr, token string) (*api.Client, error) {
	cfg := api.DefaultConfig()
	cfg.Address = serverAddr
	cfg.Token = token
	return api.NewClient(cfg)
}

// ServiceExists verifies if a service with a given name exists in Consul's catalog.
func ServiceExists(consulClient *api.Client, serviceName string, queryOpts *api.QueryOptions) (bool, error) {
	services, err := listServices(consulClient, queryOpts)
	if err != nil {
		return false, err
	}

	_, ok := services[serviceName]
	return ok, nil
}

func listServices(consulClient *api.Client, opts *api.QueryOptions) (map[string][]string, error) {
	services, _, err := consulClient.Catalog().Services(opts)
	if err != nil {
		return nil, err
	}

	return services, nil
}
