// This code is intended to run as an additional container in Task
// to help us monitor shutdown behavior of applications.
//
// It will wait until it receives a SIGTERM. Then, it will spawn
// "monitor" threads which repeatedly make requests to certain URLs,
// and logs the responses to those requests (which we can then analyze
// after the fact from CloudWatch logs).

package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

const (
	// MonitorTimeoutSeconds How long a "monitor" thread is allowed to run
	MonitorTimeoutSeconds = 30
	// MonitorIntervalSeconds Sleep time between requests in "monitor" threads
	MonitorIntervalSeconds = 1
	// HttpRequestTimeoutSeconds Timeout on individual HTTP requests
	HttpRequestTimeoutSeconds = 5
)

// monitor Repeatedly make HTTP requests to the url until the context is cancelled.
func monitor(logPrefix, url string, ctx context.Context) {
	log.Printf("%s: monitoring %s", logPrefix, url)
	client := http.Client{Timeout: HttpRequestTimeoutSeconds * time.Second}
	for {
		select {
		case <-time.After(MonitorIntervalSeconds * time.Second):
			resp, err := client.Get(url)
			if err != nil {
				log.Printf("%s: [ERR] GET %s (%s)", logPrefix, url, err)
			} else {
				log.Printf("%s: [OK] GET %s (%d)", logPrefix, url, resp.StatusCode)
			}
		case <-ctx.Done():
			return
		}
	}
}

func main() {
	monitors := map[string]string{
		"upstream":    "http://localhost:1234",
		"application": "http://localhost:9090",
	}

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM)

	log.Println("Waiting until sigterm")
	received := <-signals
	log.Printf("Signal received: signal=%v", received)

	// Start URL monitors
	var wg sync.WaitGroup
	for key, url := range monitors {
		wg.Add(1)
		// note: argument passing trick to avoid captured loop variable pitfall
		go func(k, u string) {
			defer wg.Done()
			ctx, cancel := context.WithTimeout(context.Background(), MonitorTimeoutSeconds*time.Second)
			defer cancel()
			monitor(k, u, ctx)
		}(key, url)
	}
	// Avoid exiting, by waiting until background goroutines are finished.
	wg.Wait()
}
