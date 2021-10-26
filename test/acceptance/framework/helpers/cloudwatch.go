package helpers

import (
	"encoding/json"
	"sort"
	"strings"
	"time"

	"github.com/gruntwork-io/terratest/modules/shell"
	terratestTesting "github.com/gruntwork-io/terratest/modules/testing"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
)

// GetCloudWatchLogEvents fetches all log events for the given log stream.
func GetCloudWatchLogEvents(t terratestTesting.TestingT, testConfig *config.TestConfig, streamName string) (LogMessages, error) {
	getLogs := func(nextToken string) (listLogEventsResponse, error) {
		args := []string{
			"aws", "logs", "get-log-events",
			"--region", testConfig.Region,
			"--log-group-name", testConfig.LogGroupName,
			"--log-stream-name", streamName,
		}
		if nextToken != "" {
			args = append(args, "--next-token", nextToken)
		}
		var resp listLogEventsResponse
		getLogEventsOut, err := shell.RunCommandAndGetOutputE(t, shell.Command{Command: args[0], Args: args[1:]})
		if err != nil {
			return resp, err
		}

		err = json.Unmarshal([]byte(getLogEventsOut), &resp)
		return resp, err
	}

	resp, err := getLogs("")
	if err != nil {
		return nil, err
	}

	events := resp.Events
	forwardToken := resp.NextForwardToken
	backwardToken := resp.NextBackwardToken

	// Collect log events in the backwards direction
	for {
		resp, err = getLogs(backwardToken)
		if err != nil {
			return nil, err
		}
		events = append(resp.Events, events...)
		// "If you have reached the end of the stream, it returns the same token you passed in."
		if backwardToken == resp.NextBackwardToken {
			break
		}
		backwardToken = resp.NextBackwardToken
	}

	// Collect log events in the forwards direction
	for {
		resp, err = getLogs(forwardToken)
		if err != nil {
			return nil, err
		}
		events = append(events, resp.Events...)
		// "If you have reached the end of the stream, it returns the same token you passed in."
		if forwardToken == resp.NextForwardToken {
			break
		}
		forwardToken = resp.NextForwardToken
	}
	result := LogMessages(events)
	result.Sort()
	return result, nil
}

type LogMessages []LogEvent

type LogEvent struct {
	Timestamp int64  `json:"timestamp"`
	Message   string `json:"message"`
	Ingestion int64  `json:"ingestion"`
}

type listLogEventsResponse struct {
	Events            []LogEvent `json:"events"`
	NextForwardToken  string     `json:"nextForwardToken"`
	NextBackwardToken string     `json:"nextBackwardToken"`
}

// Sort will sort these log events by timestamp.
func (lm LogMessages) Sort() {
	sort.Slice(lm, func(i, j int) bool { return lm[i].Timestamp < lm[j].Timestamp })
}

// Filter return those log events that contain any of the filterStrings.
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
	// CloudWatch timestamps are in milliseconds
	return time.Duration(int64(time.Millisecond) * (last.Timestamp - first.Timestamp))
}
