//go:build linux

package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"golang.org/x/sys/unix"

	"github.com/Chunlion/VPS-Optimize/internal/mux"
)

func TestSpliceCopyBackpressureTimeout(t *testing.T) {
	pair := func() (*net.TCPConn, *net.TCPConn) {
		ln, err := net.ListenTCP("tcp", &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1)})
		if err != nil {
			t.Fatal(err)
		}
		defer ln.Close()
		peer, err := net.DialTCP("tcp", nil, ln.Addr().(*net.TCPAddr))
		if err != nil {
			t.Fatal(err)
		}
		conn, err := ln.AcceptTCP()
		if err != nil {
			peer.Close()
			t.Fatal(err)
		}
		t.Cleanup(func() { conn.Close(); peer.Close() })
		return conn, peer
	}
	src, sender := pair()
	dst, receiver := pair()
	if err := dst.SetWriteBuffer(4096); err != nil {
		t.Fatal(err)
	}
	if err := receiver.SetReadBuffer(4096); err != nil {
		t.Fatal(err)
	}
	go func() { _, _ = sender.Write(make([]byte, 8*1024*1024)) }()
	done := make(chan error, 1)
	go func() { _, err := spliceCopy(dst, src, 4096, 50*time.Millisecond); done <- err }()
	select {
	case err := <-done:
		if !errors.Is(err, mux.ErrIdleTimeout) {
			t.Fatalf("error = %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("splice remained blocked on a slow receiver")
	}
}

func TestWaitFDWithoutTimeoutWaitsForData(t *testing.T) {
	var fds [2]int
	if err := unix.Pipe2(fds[:], unix.O_NONBLOCK|unix.O_CLOEXEC); err != nil {
		t.Fatal(err)
	}
	defer unix.Close(fds[0])
	defer unix.Close(fds[1])
	done := make(chan error, 1)
	go func() { done <- waitFD(fds[0], unix.POLLIN, 0) }()
	select {
	case err := <-done:
		t.Fatalf("returned before data: %v", err)
	case <-time.After(20 * time.Millisecond):
	}
	if _, err := unix.Write(fds[1], []byte{1}); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("did not wake for data")
	}
}

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
	status.mutations.Add(1)

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
	status.writeMu.Lock()
	written := status.lastWrittenRevision
	status.writeMu.Unlock()
	if written != 0 {
		t.Fatalf("failed write must not mark revision as written: %d", written)
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

	status.writeMu.Lock()
	written := status.lastWrittenRevision
	status.writeMu.Unlock()
	pending := status.mutations.Load()
	if written >= pending {
		t.Fatalf("concurrent update must stay pending: written revision %d, mutations %d", written, pending)
	}
	if active := status.snapshot().ActiveConnections; active != 1 {
		t.Fatalf("active connections = %d, want 1", active)
	}
}

func TestStatusTracksStrictSNIGateSeparately(t *testing.T) {
	status := newStatusTracker([]string{"127.0.0.1:443"}, 10)
	status.RecordConnection(mux.Match{RouteName: "strict_sni_gate", Blocked: true}, "unknown.example.com", "", false, 0, 0, false, false, nil)
	status.RecordConnection(mux.Match{RouteName: "panel", Blocked: true}, "panel.example.com", "", false, 0, 0, false, false, nil)

	snap := status.snapshot()
	if snap.UnknownSNIBlocked != 1 || snap.WhitelistBlocked != 1 || snap.RejectedConnections != 2 {
		t.Fatalf("unexpected blocked counters: %+v", snap)
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
	var current atomic.Pointer[runtimeConfig]
	current.Store(&runtimeConfig{cfg: mux.DefaultConfig(), d: mux.Durations{}})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		acceptLoop(ctx, ln, &current, nil, status, nil, &wg)
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
	t.Run("copy", func(t *testing.T) { testHandleConnRoutesClientHello(t, false) })
	t.Run("splice", func(t *testing.T) { testHandleConnRoutesClientHello(t, true) })
}

func TestPeekPartialClientHello(t *testing.T) {
	small := makeTestClientHello(t, "panel.example.com")
	protocols := make([]string, 24)
	for i := range protocols {
		protocols[i] = strings.Repeat("a", 255)
	}
	large := makeTestClientHello(t, "panel.example.com", protocols...)
	// 超过旧的 4KB 初始窥探窗口，验证分批到达时仍能等到完整 ClientHello。
	if len(large) <= 4096 {
		t.Fatal("large ClientHello does not exercise chunked arrival")
	}
	for _, tc := range []struct {
		hello   []byte
		stalled bool
	}{{small, false}, {large, false}, {small, true}} {
		hello, stalled := tc.hello, tc.stalled
		ln, err := net.ListenTCP("tcp", &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1)})
		if err != nil {
			t.Fatal(err)
		}
		client, err := net.DialTCP("tcp", nil, ln.Addr().(*net.TCPAddr))
		if err != nil {
			ln.Close()
			t.Fatal(err)
		}
		server, err := ln.AcceptTCP()
		ln.Close()
		if err != nil {
			client.Close()
			t.Fatal(err)
		}
		t.Cleanup(func() { client.Close(); server.Close() })
		if _, err := client.Write(hello[:1]); err != nil {
			t.Fatal(err)
		}
		if !stalled {
			go func() { time.Sleep(30 * time.Millisecond); _, _ = client.Write(hello[1:]) }()
		}
		sni, err := peek(server, 150*time.Millisecond)
		if stalled {
			if !errors.Is(err, errPeekTimeout) {
				t.Fatalf("stalled peek error = %v", err)
			}
			continue
		}
		if err != nil || sni != "panel.example.com" {
			t.Fatalf("peek sni = %q, error = %v", sni, err)
		}
		if err := server.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
			t.Fatal(err)
		}
		read := make([]byte, len(hello))
		if _, err := io.ReadFull(server, read); err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(read, hello) {
			t.Fatal("peek consumed or changed the ClientHello")
		}
	}
}

func testHandleConnRoutesClientHello(t *testing.T, splice bool) {
	t.Helper()
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
	cfg.Splice.Enabled = splice
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

	snap := status.snapshot()
	if snap.TotalConnections != 1 || snap.RouteHits["panel"] != 1 {
		t.Fatalf("unexpected routed connection status: %+v", snap)
	}
	if snap.BytesClientToBackend != uint64(len(hello)) || snap.BytesBackendToClient != uint64(len(backendReply)) {
		t.Fatalf("unexpected byte counters: %+v", snap)
	}
	if splice && snap.SpliceSuccess != 1 {
		t.Fatalf("splice was not used: %+v", snap)
	}
}

func TestReloadRuntimeConfigSwapsAndKeepsPreviousOnError(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "vpso-mux.yaml")
	valid := []byte(`
listen:
  tcp:
    - "127.0.0.1:443"
default_backend: "127.0.0.1:1443"
routes:
  - name: "panel"
    sni:
      - "panel.example.com"
    backend: "127.0.0.1:8443"
`)
	if err := os.WriteFile(path, valid, 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	var current atomic.Pointer[runtimeConfig]
	current.Store(&runtimeConfig{cfg: mux.DefaultConfig()})
	reloadRuntimeConfig(path, &current, nil)

	rc := current.Load()
	if rc == nil || rc.cfg == nil || len(rc.cfg.Routes) != 1 || rc.cfg.Routes[0].Name != "panel" {
		t.Fatalf("reload did not install the new config: %+v", rc)
	}
	if rc.d.Peek != 3*time.Second {
		t.Fatalf("reload did not derive durations: %+v", rc.d)
	}

	if err := os.WriteFile(path, []byte("listen:\n  tcp: []\n"), 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	before := current.Load()
	reloadRuntimeConfig(path, &current, nil)
	if current.Load() != before {
		t.Fatal("invalid config must not replace the active one")
	}
}

func TestHandleConnSendsProxyProtocolV1(t *testing.T) {
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
		reader := bufio.NewReader(conn)
		header, err := reader.ReadString('\n')
		if err != nil {
			backendDone <- err
			return
		}
		if !strings.HasPrefix(header, "PROXY TCP4 127.0.0.1 ") || !strings.HasSuffix(header, "\r\n") {
			backendDone <- fmt.Errorf("unexpected proxy header: %q", header)
			return
		}
		rest := make([]byte, len(hello))
		if _, err := io.ReadFull(reader, rest); err != nil {
			backendDone <- err
			return
		}
		if !bytes.Equal(rest, hello) {
			backendDone <- errors.New("ClientHello corrupted after proxy header")
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
	cfg.Routes = []mux.Route{{
		Name:          "panel",
		SNI:           []string{"panel.example.com"},
		Backend:       backendLn.Addr().String(),
		ProxyProtocol: "v1",
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
}

func makeTestClientHello(t *testing.T, serverName string, nextProtos ...string) []byte {
	t.Helper()
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()

	errCh := make(chan error, 1)
	go func() {
		errCh <- tls.Client(client, &tls.Config{ServerName: serverName, InsecureSkipVerify: true, NextProtos: nextProtos}).Handshake()
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
