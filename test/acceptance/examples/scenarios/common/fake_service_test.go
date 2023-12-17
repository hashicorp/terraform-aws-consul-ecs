// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package common

import (
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestGetFakeServiceResponse(t *testing.T) {
	cases := map[string]struct {
		httpRespCode int
		respStr      string
		wantErr      bool
		errStr       string
		expectedResp *FakeServiceResponse
	}{
		"non success error code": {
			httpRespCode: http.StatusInternalServerError,
			wantErr:      true,
		},
		"json unmarshalling error": {
			httpRespCode: http.StatusOK,
			respStr:      `unsupported-response-format`,
			wantErr:      true,
			errStr:       "unmarshalling json",
		},
		"failed upstream call": {
			httpRespCode: http.StatusOK,
			respStr:      "{\n  \"name\": \"consul-ecs-example-client-app\",\n  \"uri\": \"/\",\n  \"type\": \"HTTP\",\n  \"ip_addresses\": [\n    \"169.254.172.2\",\n    \"10.0.3.165\"\n  ],\n  \"start_time\": \"2023-12-17T13:14:48.498808\",\n  \"end_time\": \"2023-12-17T13:14:48.505297\",\n  \"duration\": \"6.488534ms\",\n  \"body\": \"Hello World\",\n  \"upstream_calls\": {\n    \"http://localhost:1234\": {\n      \"uri\": \"http://localhost:1234\",\n      \"code\": -1,\n      \"error\": \"Error communicating with upstream service: Get \\\"http://localhost:1234/\\\": EOF\"\n    }\n  },\n  \"code\": 500\n}",
			expectedResp: &FakeServiceResponse{
				Body: "Hello World",
				Code: 500,
				UpstreamCalls: map[string]UpstreamCallResponse{
					"http://localhost:1234": {
						Code: -1,
					},
				},
			},
		},
		"successful upstream call": {
			httpRespCode: http.StatusOK,
			respStr:      "{\n  \"name\": \"consul-ecs-example-client-app\",\n  \"uri\": \"/\",\n  \"type\": \"HTTP\",\n  \"ip_addresses\": [\n    \"169.254.172.2\",\n    \"10.0.3.165\"\n  ],\n  \"start_time\": \"2023-12-17T13:01:18.291103\",\n  \"end_time\": \"2023-12-17T13:01:18.306560\",\n  \"duration\": \"15.456478ms\",\n  \"body\": \"Hello World\",\n  \"upstream_calls\": {\n    \"http://localhost:1234\": {\n      \"name\": \"consul-ecs-example-server-app\",\n      \"uri\": \"http://localhost:1234\",\n      \"type\": \"HTTP\",\n      \"ip_addresses\": [\n        \"169.254.172.2\",\n        \"10.0.2.34\"\n      ],\n      \"start_time\": \"2023-12-17T13:01:18.304883\",\n      \"end_time\": \"2023-12-17T13:01:18.305302\",\n      \"duration\": \"418.719µs\",\n      \"headers\": {\n        \"Content-Length\": \"298\",\n        \"Content-Type\": \"text/plain; charset=utf-8\",\n        \"Date\": \"Sun, 17 Dec 2023 13:01:18 GMT\"\n      },\n      \"body\": \"Hello World\",\n      \"code\": 200\n    }\n  },\n  \"code\": 200\n}",
			expectedResp: &FakeServiceResponse{
				Body: "Hello World",
				Code: 200,
				UpstreamCalls: map[string]UpstreamCallResponse{
					"http://localhost:1234": {
						Name: "consul-ecs-example-server-app",
						Body: "Hello World",
						Code: 200,
					},
				},
			},
		},
	}

	for name, c := range cases {
		c := c
		t.Run(name, func(t *testing.T) {
			handler := http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				w.WriteHeader(c.httpRespCode)
				_, _ = w.Write([]byte(c.respStr))
			})
			server := httptest.NewServer(handler)
			t.Cleanup(server.Close)

			resp, err := GetFakeServiceResponse(server.URL)
			if c.wantErr {
				require.Error(t, err)
				if c.errStr != "" {
					require.Contains(t, err.Error(), c.errStr)
				}
			} else {
				require.NotNil(t, resp)
				require.True(t, reflect.DeepEqual(resp, c.expectedResp))
			}
		})
	}
}
