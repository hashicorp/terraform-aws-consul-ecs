package perf

import (
	"fmt"
	"testing"
	"time"

	"github.com/armon/go-metrics"
	"github.com/armon/go-metrics/datadog"
	"github.com/stretchr/testify/require"
)

func InitMetrics(t *testing.T) {
	datadogAddress := "127.0.0.1:8125"
	defaultConfig := metrics.DefaultConfig("consul-ecs-perf")

	sink, err := datadog.NewDogStatsdSink(datadogAddress, "")
	require.NoError(t, err)

	_, err = metrics.NewGlobal(defaultConfig, sink)
	require.NoError(t, err)
}

func RecordDuration(d time.Duration, serviceGroup int) {
	val := float32(d) / float32(time.Millisecond)
	metrics.AddSampleWithLabels([]string{"stabilization"}, val, []metrics.Label{
		{Name: "service-group", Value: fmt.Sprint(serviceGroup)},
	})
}
