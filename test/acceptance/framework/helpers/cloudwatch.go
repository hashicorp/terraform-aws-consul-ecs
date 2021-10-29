package helpers

import (
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/shell"
	terratestTesting "github.com/gruntwork-io/terratest/modules/testing"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
	"github.com/stretchr/testify/require"
)

// GetCloudWatchLogEvents fetches all log events for the given container.
func GetCloudWatchLogEvents(t terratestTesting.TestingT, testConfig *config.TestConfig, taskId, containerName string) (LogMessages, error) {
	args := []string{
		"ecs-cli", "logs",
		"--region", testConfig.Region,
		"--cluster", testConfig.ECSClusterARN,
		"--task-id", taskId,
		"--container-name", containerName,
		"--timestamps",
	}
	out, err := shell.RunCommandAndGetOutputE(t, shell.Command{Command: args[0], Args: args[1:]})
	if err != nil {
		return nil, err
	}

	// Parse into LogEvents
	var result LogMessages
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if len(line) == 0 {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		timestamp, err := time.Parse(time.RFC3339, parts[0])
		if err != nil {
			t.Errorf("failed to parse timestamp in log line `%s`", line)
			return nil, err
		}
		result = append(result, LogEvent{timestamp, parts[1]})
	}
	return result, nil
}

// WaitForLogEvents waits until all the given messages are found in the container logs.
// It checks for a minimum number of occurrences of each log message, and a minimum
// timespan for those log messages.
func WaitForLogEvents(t *testing.T, testConfig *config.TestConfig, taskId, containerName string,
	minMessageCounts map[string]int, minDuration time.Duration,
) {
	messages := make([]string, len(minMessageCounts))

	t.Logf("Waiting for log messages in container %s, messages=%v", containerName, messages)
	retry.RunWith(&retry.Timer{Timeout: 2 * time.Minute, Wait: 30 * time.Second}, t, func(r *retry.R) {
		logs, err := GetCloudWatchLogEvents(t, testConfig, taskId, containerName)
		require.NoError(r, err)

		logs = logs.Filter(messages...)
		for message, count := range minMessageCounts {
			require.GreaterOrEqual(r, len(logs.Filter(message)), count)
		}
		require.GreaterOrEqual(r, logs.Duration(), minDuration)
	})
}

type LogMessages []LogEvent

type LogEvent struct {
	Timestamp time.Time
	Message   string
}

// Sort will sort these log events by timestamp.
func (lm LogMessages) Sort() {
	sort.Slice(lm, func(i, j int) bool {
		return lm[i].Timestamp.Before(lm[j].Timestamp)
	})
}

// Filter returns those log events that contain any of the filterStrings.
func (lm LogMessages) Filter(filterStrings ...string) LogMessages {
	var result []LogEvent
	for _, event := range lm {
		for _, filterStr := range filterStrings {
			if strings.Contains(event.Message, filterStr) {
				result = append(result, event)
			}
		}
	}
	return result
}

// Duration returns the difference between the max and min log timestamps.
// Returns a zero duration if there are zero or one log events.
func (lm LogMessages) Duration() time.Duration {
	if len(lm) < 2 {
		return 0
	}
	lm.Sort() // Ensure sorted by timestamp first
	last := lm[len(lm)-1]
	first := lm[0]
	return last.Timestamp.Sub(first.Timestamp)
}
