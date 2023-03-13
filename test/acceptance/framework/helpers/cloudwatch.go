// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package helpers

import (
	"sort"
	"strings"
	"time"

	"github.com/gruntwork-io/terratest/modules/shell"
	terratestTesting "github.com/gruntwork-io/terratest/modules/testing"
	"github.com/hashicorp/terraform-aws-consul-ecs/test/acceptance/framework/config"
)

// GetCloudWatchLogEvents fetches all log events for the given container.
func GetCloudWatchLogEvents(t terratestTesting.TestingT, testConfig *config.TestConfig, clusterARN, taskId, containerName string) (LogMessages, error) {
	args := []string{
		"ecs-cli", "logs",
		"--region", testConfig.Region,
		"--cluster", clusterARN,
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
			t.Errorf("failed to parse timestamp in CloudWatch log line: %q", line)
			return nil, err
		}
		msg := ""
		if len(parts) > 1 {
			msg = parts[1]
		}
		result = append(result, LogEvent{timestamp, msg})
	}
	return result, nil
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
