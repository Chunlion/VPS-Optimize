//go:build linux

package main

import (
	"bytes"
	"errors"
	"log"
	"net"
	"strings"
	"testing"
	"time"
)

func TestDialBackendWithRetryDefaultDoesNotRetry(t *testing.T) {
	calls := 0
	_, stats, err := dialBackendWithRetry("127.0.0.1:1", time.Second, 0, 0, func(network, address string, timeout time.Duration) (net.Conn, error) {
		calls++
		return nil, errors.New("dial failed")
	})
	if err == nil {
		t.Fatal("expected dial error")
	}
	if calls != 1 {
		t.Fatalf("calls = %d, want 1", calls)
	}
	if stats.attempts != 0 || stats.success || stats.failed {
		t.Fatalf("stats = %+v, want no retry stats", stats)
	}
}

func TestDialBackendWithRetrySuccess(t *testing.T) {
	calls := 0
	var server net.Conn
	conn, stats, err := dialBackendWithRetry("127.0.0.1:1", time.Second, 1, 0, func(network, address string, timeout time.Duration) (net.Conn, error) {
		calls++
		if calls == 1 {
			return nil, errors.New("temporary backend failure")
		}
		client, peer := net.Pipe()
		server = peer
		return client, nil
	})
	if err != nil {
		t.Fatalf("dialBackendWithRetry: %v", err)
	}
	defer conn.Close()
	defer server.Close()
	if calls != 2 {
		t.Fatalf("calls = %d, want 2", calls)
	}
	if stats.attempts != 1 || !stats.success || stats.failed {
		t.Fatalf("stats = %+v, want one successful retry", stats)
	}
}

func TestDialBackendWithRetryFailure(t *testing.T) {
	calls := 0
	_, stats, err := dialBackendWithRetry("127.0.0.1:1", time.Second, 2, 0, func(network, address string, timeout time.Duration) (net.Conn, error) {
		calls++
		return nil, errors.New("dial failed")
	})
	if err == nil {
		t.Fatal("expected dial error")
	}
	if calls != 3 {
		t.Fatalf("calls = %d, want 3", calls)
	}
	if stats.attempts != 2 || stats.success || !stats.failed {
		t.Fatalf("stats = %+v, want two failed retries", stats)
	}
}

func TestStatusWriteFailureIsRateLimitedAndNonFatal(t *testing.T) {
	status := newStatusTracker([]string{"127.0.0.1:443"}, 10)
	status.path = t.TempDir()
	status.dirty = true

	var logs bytes.Buffer
	oldOutput := log.Writer()
	oldFlags := log.Flags()
	log.SetOutput(&logs)
	log.SetFlags(0)
	defer func() {
		log.SetOutput(oldOutput)
		log.SetFlags(oldFlags)
	}()

	status.Write()
	status.Flush()

	output := logs.String()
	if count := strings.Count(output, "failed to write status json"); count != 1 {
		t.Fatalf("status write error log count = %d, want 1; logs: %s", count, output)
	}
	if !strings.Contains(output, status.path) {
		t.Fatalf("status write error log missing path %q: %s", status.path, output)
	}
	if !status.dirty {
		t.Fatalf("status should remain dirty after write failure")
	}
}
