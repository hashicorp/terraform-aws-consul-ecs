// Copyright IBM Corp. 2021, 2025
// SPDX-License-Identifier: MPL-2.0

package basic

import (
	"os"
	"testing"

	testsuite "github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/suite"
)

var suite testsuite.Suite

func TestMain(m *testing.M) {
	suite = testsuite.NewSuite(m)
	os.Exit(suite.Run())
}
