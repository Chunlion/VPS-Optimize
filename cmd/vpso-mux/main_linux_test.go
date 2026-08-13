//go:build linux

package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/Chunlion/VPS-Optimize/internal/mux"
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

func TestStatusWriteDoesNotBlockConcurrentUpdates(t *testing.T) {
	status := newStatusTracker([]string{"127.0.0.1:443"}, 10)
	writeStarted := make(chan struct{})
	releaseWrite := make(chan struct{})
	writeDone := make(chan struct{})
	status.writePayload = func([]byte) error {
		close(writeStarted)
		<-releaseWrite
		return nil
	}

	go func() {
		status.Write()
		close(writeDone)
	}()
	<-writeStarted

	updateDone := make(chan struct{})
	go func() {
		status.RecordAccepted()
		close(updateDone)
	}()
	select {
	case <-updateDone:
	case <-time.After(time.Second):
		t.Fatal("status update blocked by status file write")
	}

	close(releaseWrite)
	select {
	case <-writeDone:
	case <-time.After(time.Second):
		t.Fatal("status write did not finish")
	}

	status.mu.Lock()
	dirty := status.dirty
	active := status.data.ActiveConnections
	status.mu.Unlock()
	if !dirty {
		t.Fatal("concurrent update must remain dirty after older snapshot is written")
	}
	if active != 1 {
		t.Fatalf("active connections = %d, want 1", active)
	}
}

func TestStatusTracksStrictSNIGateSeparately(t *testing.T) {
	status := newStatusTracker([]string{"127.0.0.1:443"}, 10)
	status.RecordConnection(mux.Match{RouteName: "strict_sni_gate", Blocked: true}, "unknown.example.com", "", false, 0, 0, false, false, nil)
	status.RecordConnection(mux.Match{RouteName: "panel", Blocked: true}, "panel.example.com", "", false, 0, 0, false, false, nil)

	status.mu.Lock()
	defer status.mu.Unlock()
	if status.data.UnknownSNIBlocked != 1 || status.data.WhitelistBlocked != 1 || status.data.RejectedConnections != 2 {
		t.Fatalf("unexpected blocked counters: %+v", status.data)
	}
}

func TestConnectionLimiterEnforcesLimit(t *testing.T) {
	limiter := newConnectionLimiter(1)
	if !limiter.Acquire() {
		t.Fatal("first connection must be accepted")
	}
	if limiter.Acquire() {
		t.Fatal("connection above the limit must be rejected")
	}
	limiter.Release()
	if !limiter.Acquire() {
		t.Fatal("released capacity must be reusable")
	}
	limiter.Release()
	limiter.Release()

	if limiter := newConnectionLimiter(0); limiter != nil {
		t.Fatal("zero connection limit must disable the limiter")
	}
}

func TestWaitForShutdownCompletionAndTimeout(t *testing.T) {
	var wg sync.WaitGroup
	if !waitForShutdown(&wg, time.Second) {
		t.Fatal("completed wait group reported a timeout")
	}

	wg.Add(1)
	if waitForShutdown(&wg, 20*time.Millisecond) {
		t.Fatal("blocked wait group must time out")
	}
	wg.Done()
	if !waitForShutdown(&wg, time.Second) {
		t.Fatal("released wait group did not complete")
	}
}

func TestWriteStatusPayloadIsAtomicJSONWithExpectedMode(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "state", "status.json")
	payload := []byte("{\"active_connections\":1}\n")

	if err := writeStatusPayload(path, payload); err != nil {
		t.Fatalf("writeStatusPayload: %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if !bytes.Equal(data, payload) || !json.Valid(data) {
		t.Fatalf("status payload = %q, want valid JSON %q", data, payload)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if mode := info.Mode().Perm(); mode != 0644 {
		t.Fatalf("status mode = %04o, want 0644", mode)
	}
	tmpFiles, err := filepath.Glob(filepath.Join(filepath.Dir(path), "status.*.tmp"))
	if err != nil {
		t.Fatalf("Glob: %v", err)
	}
	if len(tmpFiles) != 0 {
		t.Fatalf("temporary status files left behind: %v", tmpFiles)
	}
}

func TestAcceptLoopStopsAfterContextCancellation(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("Listen: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	status := newStatusTracker([]string{ln.Addr().String()}, 1)
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		acceptLoop(ctx, ln, mux.DefaultConfig(), mux.Durations{}, nil, status, nil, &wg)
	}()

	cancel()
	if err := ln.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if !waitForShutdown(&wg, time.Second) {
		t.Fatal("accept loop did not stop after cancellation")
	}
}

func TestHandleConnRoutesClientHelloOverLoopback(t *testing.T) {
	backendLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("backend Listen: %v", err)
	}
	defer backendLn.Close()

	hello := makeTestClientHello(t, "panel.example.com")
	backendReply := []byte("backend-ok")
	backendDone := make(chan error, 1)
	go func() {
		conn, err := backendLn.Accept()
		if err != nil {
			backendDone <- err
			return
		}
		defer conn.Close()
		got, err := io.ReadAll(conn)
		if err != nil {
			backendDone <- err
			return
		}
		if !bytes.Equal(got, hello) {
			backendDone <- errors.New("backend did not receive the original ClientHello")
			return
		}
		_, err = conn.Write(backendReply)
		backendDone <- err
	}()

	frontendLn, err := net.ListenTCP("tcp", &net.TCPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		t.Fatalf("frontend ListenTCP: %v", err)
	}
	defer frontendLn.Close()

	cfg := mux.DefaultConfig()
	cfg.Listen.TCP = []string{frontendLn.Addr().String()}
	cfg.DefaultBackend = backendLn.Addr().String()
	cfg.Splice.Enabled = false
	cfg.Routes = []mux.Route{{
		Name:    "panel",
		SNI:     []string{"panel.example.com"},
		Backend: backendLn.Addr().String(),
	}}
	if _, err := mux.ValidateConfig(cfg); err != nil {
		t.Fatalf("ValidateConfig: %v", err)
	}
	durations, err := cfg.Durations()
	if err != nil {
		t.Fatalf("Durations: %v", err)
	}
	status := newStatusTracker(cfg.Listen.TCP, cfg.Limits.MaxConnections)
	handlerDone := make(chan struct{})
	go func() {
		conn, acceptErr := frontendLn.AcceptTCP()
		if acceptErr == nil {
			handleConn(conn, cfg, durations, nil, status)
		}
		close(handlerDone)
	}()

	client, err := net.DialTCP("tcp", nil, frontendLn.Addr().(*net.TCPAddr))
	if err != nil {
		t.Fatalf("DialTCP: %v", err)
	}
	if _, err := client.Write(hello); err != nil {
		client.Close()
		t.Fatalf("client Write: %v", err)
	}
	if err := client.CloseWrite(); err != nil {
		client.Close()
		t.Fatalf("client CloseWrite: %v", err)
	}
	if err := client.SetReadDeadline(time.Now().Add(2 * time.Second)); err != nil {
		client.Close()
		t.Fatalf("client SetReadDeadline: %v", err)
	}
	reply := make([]byte, len(backendReply))
	if _, err := io.ReadFull(client, reply); err != nil {
		client.Close()
		t.Fatalf("client ReadFull: %v", err)
	}
	client.Close()
	if !bytes.Equal(reply, backendReply) {
		t.Fatalf("reply = %q, want %q", reply, backendReply)
	}

	select {
	case err := <-backendDone:
		if err != nil {
			t.Fatalf("backend: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("backend did not finish")
	}
	select {
	case <-handlerDone:
	case <-time.After(2 * time.Second):
		t.Fatal("connection handler did not finish")
	}

	status.mu.Lock()
	defer status.mu.Unlock()
	if status.data.TotalConnections != 1 || status.data.RouteHits["panel"] != 1 {
		t.Fatalf("unexpected routed connection status: %+v", status.data)
	}
	if status.data.BytesClientToBackend != uint64(len(hello)) || status.data.BytesBackendToClient != uint64(len(backendReply)) {
		t.Fatalf("unexpected byte counters: %+v", status.data)
	}
}

func makeTestClientHello(t *testing.T, serverName string) []byte {
	t.Helper()
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()

	errCh := make(chan error, 1)
	go func() {
		errCh <- tls.Client(client, &tls.Config{ServerName: serverName, InsecureSkipVerify: true}).Handshake()
	}()
	buf := make([]byte, maxPeekSize)
	n, err := server.Read(buf)
	if err != nil {
		t.Fatalf("read ClientHello: %v", err)
	}
	server.Close()
	<-errCh
	return append([]byte(nil), buf[:n]...)
}
