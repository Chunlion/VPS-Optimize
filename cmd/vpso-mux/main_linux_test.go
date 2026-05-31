//go:build linux

package main

import (
	"errors"
	"net"
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
