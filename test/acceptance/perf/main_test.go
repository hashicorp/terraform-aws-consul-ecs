package perf

import (
	"os"
	"testing"
)

var testSuite Suite

func TestMain(m *testing.M) {
	testSuite = NewSuite(m)
	os.Exit(testSuite.Run())
}
