// Copyright IBM Corp. 2021, 2025
// SPDX-License-Identifier: MPL-2.0

package common

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/stretchr/testify/require"
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

// ValidateFakeServiceResponse takes in the client application's address(typically
// the address of the ALB infront of the client app's ECS task) and performs a
// HTTP GET against the same. It also verifies if the response matches the
// success criteria and also verifies if the expected upstream app was hit.
func ValidateFakeServiceResponse(t *testing.T, lbURL, expectedUpstream string) *UpstreamCallResponse {
	var upstreamResp UpstreamCallResponse
	retry.RunWith(&retry.Timer{Timeout: 3 * time.Minute, Wait: 10 * time.Second}, t, func(r *retry.R) {
		resp, err := GetFakeServiceResponse(lbURL)
		require.NoError(r, err)

		require.Equal(r, 200, resp.Code)
		require.Equal(r, "Hello World", resp.Body)
		require.NotNil(r, resp.UpstreamCalls)

		upstreamResp = resp.UpstreamCalls["http://localhost:1234"]
		require.NotNil(r, upstreamResp)
		require.Equal(r, expectedUpstream, upstreamResp.Name)
		require.Equal(r, 200, upstreamResp.Code)
		require.Equal(r, "Hello World", upstreamResp.Body)
	})

	return &upstreamResp
}

// GetFakeServiceResponse takes in the client application's address(typically
// the address of the ALB infront of the client app's ECS task) and performs
// a HTTP GET against the same. It returns back some fields of the response
// json which can be used by the caller to validate if the request went
// through as expected.
func GetFakeServiceResponse(addr string) (*FakeServiceResponse, error) {
	resp, err := HTTPGet(addr)
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

func HTTPGet(addr string) ([]byte, error) {
	resp, err := http.Get(addr)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}
