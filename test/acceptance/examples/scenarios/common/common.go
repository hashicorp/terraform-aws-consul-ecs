// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package common

import (
	"io"
	"math/rand"
	"net/http"
	"strings"
)

const (
	characterSet = "abcdefghijklmnopqrstuvwxyz"
)

// This method relies on a third party API to retrieve
// the public IP of the host where this test runs.
func GetPublicIP() (string, error) {
	resp, err := http.Get("https://api64.ipify.org?format=text")
	if err != nil {
		return "", err
	}
	defer func() {
		_ = resp.Body.Close()
	}()

	ip, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	return string(ip), nil
}

// GenerateRandomStr generate a random string of a given length
// from the predefined characterSet.
//
// Note: The resulting string is always lowercased.
func GenerateRandomStr(length int) string {
	result := make([]byte, length)
	for i := range result {
		result[i] = characterSet[rand.Intn(len(characterSet))]
	}
	return strings.ToLower(string(result))
}
