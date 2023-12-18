// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package common

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

type FakeServiceResponse struct {
	Body          string                          `json:"body"`
	Code          int                             `json:"code"`
	UpstreamCalls map[string]UpstreamCallResponse `json:"upstream_calls"`
}

type UpstreamCallResponse struct {
	Name        string   `json:"name"`
	Body        string   `json:"body"`
	IpAddresses []string `json:"ip_addresses,omitempty"`
	Code        int      `json:"code"`
}

// GetFakeServiceResponse takes in the client application's address(typically
// the address of the ALB infront of the client app's ECS task) and performs
// a HTTP GET against the same. It returns back some fields of the response
// json which can be used by the caller to validate if the request went
// through as expected.
func GetFakeServiceResponse(addr string) (*FakeServiceResponse, error) {
	resp, err := httpGet(addr)
	if err != nil {
		return nil, err
	}

	var fakeSvcResp *FakeServiceResponse
	err = json.Unmarshal(resp, &fakeSvcResp)
	if err != nil {
		return nil, fmt.Errorf("unmarshalling json %w", err)
	}

	return fakeSvcResp, nil
}

func httpGet(addr string) ([]byte, error) {
	resp, err := http.Get(addr)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}
