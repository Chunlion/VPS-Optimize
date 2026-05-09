package mux

import (
	"io"
	"net"
	"testing"
	"time"
)

func TestSpliceUnavailableFallsBackToCopy(t *testing.T) {
	srcConn, srcPeer := tcpPair(t)
	defer srcConn.Close()
	defer srcPeer.Close()
	dstConn, dstPeer := tcpPair(t)
	defer dstConn.Close()
	defer dstPeer.Close()

	done := make(chan struct {
		mode string
		err  error
	}, 1)
	go func() {
		mode, err := copyDirection(dstConn, srcConn, TransferOptions{
			SpliceEnabled:  true,
			FallbackToCopy: true,
			IdleTimeout:    time.Second,
			SpliceCopy: func(_ *net.TCPConn, _ *net.TCPConn, _ int) (int64, error) {
				return 0, ErrSpliceUnavailable
			},
		})
		done <- struct {
			mode string
			err  error
		}{mode: mode, err: err}
	}()

	if _, err := srcPeer.Write([]byte("hello")); err != nil {
		t.Fatalf("write: %v", err)
	}
	_ = srcPeer.Close()

	buf := make([]byte, 5)
	if _, err := io.ReadFull(dstPeer, buf); err != nil {
		t.Fatalf("read fallback data: %v", err)
	}
	if string(buf) != "hello" {
		t.Fatalf("fallback data = %q", string(buf))
	}
	result := <-done
	if result.err != nil {
		t.Fatalf("copyDirection returned error: %v", result.err)
	}
	if result.mode != "copy" {
		t.Fatalf("mode = %q, want copy", result.mode)
	}
}

func tcpPair(t *testing.T) (*net.TCPConn, *net.TCPConn) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer ln.Close()

	accepted := make(chan net.Conn, 1)
	go func() {
		conn, _ := ln.Accept()
		accepted <- conn
	}()
	client, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	server := <-accepted
	return server.(*net.TCPConn), client.(*net.TCPConn)
}
