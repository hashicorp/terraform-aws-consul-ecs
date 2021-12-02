package perf

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

type serviceGroupCall struct {
	stabilizedServiceGroups []int
	expected                []int
	offset                  time.Duration
}

func TestEverythingStabilizes(t *testing.T) {
	var emptyExpected []int
	now := time.Now()
	restarts := 2
	serviceGroupCount := 4

	serviceGroupCalls := []serviceGroupCall{
		{
			stabilizedServiceGroups: []int{1, 2},
			expected:                emptyExpected,
		},
		{
			stabilizedServiceGroups: []int{1, 2, 3},
			expected:                emptyExpected,
		},
		// initially stable
		{
			stabilizedServiceGroups: []int{1, 2, 3, 4},
			expected:                []int{1, 2, 3, 4},
			offset:                  1 * time.Second,
		},
		// next stable
		{
			stabilizedServiceGroups: []int{1, 2, 3, 4},
			expected:                []int{1, 2, 3, 4},
			offset:                  2 * time.Second,
		},
		// next stable
		{
			stabilizedServiceGroups: []int{1, 2, 3, 4},
			expected:                []int{1, 2, 3, 4},
			offset:                  3 * time.Second,
		},
	}

	var timeKeys []time.Time

	strategy := NewEverythingStabilizes(serviceGroupCount, restarts)

	for i, d := range serviceGroupCalls {
		eventTime := now.Add(d.offset)
		toDelete := strategy.ServiceGroupsToDelete(d.stabilizedServiceGroups, eventTime)
		require.Equal(t, d.expected, toDelete)
		if len(toDelete) > 0 {
			timeKeys = append(timeKeys, eventTime)
		}
		require.Equal(t, i == len(serviceGroupCalls)-1, strategy.Done())
	}

	data := strategy.Data()
	require.Len(t, data, restarts)
}

func TestServiceGroupStabilizes(t *testing.T) {
	now := time.Now()
	restarts := 2
	serviceGroupCount := 4

	serviceGroupCalls := []serviceGroupCall{
		{
			stabilizedServiceGroups: []int{1, 2},
			expected:                []int{1, 2},
			offset:                  1 * time.Second,
		},
		{
			stabilizedServiceGroups: []int{1, 2, 3},
			expected:                []int{1, 2, 3},
			offset:                  2 * time.Second,
		},
		{
			stabilizedServiceGroups: []int{1, 2, 3, 4},
			expected:                []int{1, 2, 3, 4},
			offset:                  3 * time.Second,
		},
		{
			stabilizedServiceGroups: []int{1, 2, 3, 4},
			expected:                []int{3, 4},
			offset:                  4 * time.Second,
		},
		{
			stabilizedServiceGroups: []int{1, 2, 3, 4},
			expected:                []int{4},
			offset:                  5 * time.Second,
		},
	}

	var timeKeys []time.Time

	strategy := NewServiceGroupStabilizes(serviceGroupCount, restarts)

	for i, d := range serviceGroupCalls {
		eventTime := now.Add(d.offset)
		toDelete := strategy.ServiceGroupsToDelete(d.stabilizedServiceGroups, eventTime)
		require.Equal(t, d.expected, toDelete)
		for range toDelete {
			timeKeys = append(timeKeys, eventTime)
		}
		require.Equal(t, i == len(serviceGroupCalls), strategy.Done())
	}

	data := strategy.Data()
	require.Len(t, data, restarts*serviceGroupCount)
}
