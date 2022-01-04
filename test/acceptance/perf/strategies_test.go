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

func toMap(keys []int) map[int]struct{} {
	m := make(map[int]struct{})
	for _, i := range keys {
		m[i] = struct{}{}
	}
	return m
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

	strategy := NewEverythingStabilizes(serviceGroupCount, restarts, 100)

	for i, d := range serviceGroupCalls {
		eventTime := now.Add(d.offset)

		toDelete := strategy.ServiceGroupsToDelete(toMap(d.stabilizedServiceGroups), eventTime)
		require.Equal(t, toMap(d.expected), toDelete)
		require.Equal(t, i == len(serviceGroupCalls)-1, strategy.Done())
	}

	data := strategy.Data()
	require.Len(t, data, restarts)
}

func TestEverythingStabilizesWithThreshold(t *testing.T) {
	var emptyExpected []int
	now := time.Now()
	restarts := 2
	serviceGroupCount := 4

	serviceGroupCalls := []serviceGroupCall{
		{
			stabilizedServiceGroups: []int{1},
			expected:                emptyExpected,
		},
		// Initial stable. Now the only service groups are 1 and 2.
		{
			stabilizedServiceGroups: []int{1, 2},
			expected:                []int{1, 2},
		},
		{
			stabilizedServiceGroups: []int{},
			expected:                emptyExpected,
		},
		// First stable. Now half of the two services are stable so we are done.
		{
			stabilizedServiceGroups: []int{1, 3},
			expected:                []int{1, 3},
		},
		// Second stable. Now the last remaining service group is stable.
		{
			stabilizedServiceGroups: []int{1},
			expected:                []int{1},
		},
	}

	strategy := NewEverythingStabilizes(serviceGroupCount, restarts, 50)

	for i, d := range serviceGroupCalls {
		eventTime := now.Add(d.offset)

		toDelete := strategy.ServiceGroupsToDelete(toMap(d.stabilizedServiceGroups), eventTime)
		require.Equal(t, toMap(d.expected), toDelete)
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

	strategy := NewServiceGroupStabilizes(serviceGroupCount, restarts)

	for i, d := range serviceGroupCalls {
		eventTime := now.Add(d.offset)

		toDelete := strategy.ServiceGroupsToDelete(toMap(d.stabilizedServiceGroups), eventTime)
		require.Equal(t, toMap(d.expected), toDelete)
		require.Equal(t, i == len(serviceGroupCalls), strategy.Done())
	}

	data := strategy.Data()
	require.Len(t, data, restarts*serviceGroupCount)
}
