package mux

import (
	"errors"
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
		mode  string
		bytes int64
		err   error
	}, 1)
	go func() {
		mode, bytes, err := copyDirection(dstConn, srcConn, TransferOptions{
			SpliceEnabled:  true,
			FallbackToCopy: true,
			IdleTimeout:    time.Second,
			SpliceCopy: func(_ *net.TCPConn, _ *net.TCPConn, _ int, _ time.Duration) (int64, error) {
				return 0, ErrSpliceUnavailable
			},
		})
		done <- struct {
			mode  string
			bytes int64
			err   error
		}{mode: mode, bytes: bytes, err: err}
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
	if result.bytes != 5 {
		t.Fatalf("bytes = %d, want 5", result.bytes)
	}
}

func TestSpliceErrorWithoutFallbackReturnsSpliceError(t *testing.T) {
	srcConn, srcPeer := tcpPair(t)
	defer srcConn.Close()
	defer srcPeer.Close()
	dstConn, dstPeer := tcpPair(t)
	defer dstConn.Close()
	defer dstPeer.Close()

	spliceErr := errors.New("splice failed")
	mode, bytes, err := copyDirection(dstConn, srcConn, TransferOptions{
		SpliceEnabled:  true,
		FallbackToCopy: false,
		IdleTimeout:    time.Second,
		SpliceCopy: func(_ *net.TCPConn, _ *net.TCPConn, _ int, _ time.Duration) (int64, error) {
			return 7, spliceErr
		},
	})
	if !errors.Is(err, spliceErr) {
		t.Fatalf("error = %v, want splice error", err)
	}
	if mode != "splice" {
		t.Fatalf("mode = %q, want splice", mode)
	}
	if bytes != 7 {
		t.Fatalf("bytes = %d, want 7", bytes)
	}
}

func TestSpliceDisabledUsesCopy(t *testing.T) {
	srcConn, srcPeer := tcpPair(t)
	defer srcConn.Close()
	defer srcPeer.Close()
	dstConn, dstPeer := tcpPair(t)
	defer dstConn.Close()
	defer dstPeer.Close()

	spliceCalled := false
	done := make(chan struct {
		mode  string
		bytes int64
		err   error
	}, 1)
	go func() {
		mode, bytes, err := copyDirection(dstConn, srcConn, TransferOptions{
			SpliceEnabled:  false,
			FallbackToCopy: true,
			IdleTimeout:    time.Second,
			SpliceCopy: func(_ *net.TCPConn, _ *net.TCPConn, _ int, _ time.Duration) (int64, error) {
				spliceCalled = true
				return 0, errors.New("should not be called")
			},
		})
		done <- struct {
			mode  string
			bytes int64
			err   error
		}{mode: mode, bytes: bytes, err: err}
	}()

	if _, err := srcPeer.Write([]byte("copy")); err != nil {
		t.Fatalf("write: %v", err)
	}
	_ = srcPeer.Close()

	buf := make([]byte, 4)
	if _, err := io.ReadFull(dstPeer, buf); err != nil {
		t.Fatalf("read copy data: %v", err)
	}
	if string(buf) != "copy" {
		t.Fatalf("copy data = %q", string(buf))
	}
	result := <-done
	if result.err != nil {
		t.Fatalf("copyDirection returned error: %v", result.err)
	}
	if result.mode != "copy" {
		t.Fatalf("mode = %q, want copy", result.mode)
	}
	if result.bytes != 4 {
		t.Fatalf("bytes = %d, want 4", result.bytes)
	}
	if spliceCalled {
		t.Fatalf("splice copy was called while splice was disabled")
	}
}

func TestCopyDirectionIdleTimeout(t *testing.T) {
	srcConn, srcPeer := tcpPair(t)
	defer srcConn.Close()
	defer srcPeer.Close()
	dstConn, dstPeer := tcpPair(t)
	defer dstConn.Close()
	defer dstPeer.Close()

	mode, bytes, err := copyDirection(dstConn, srcConn, TransferOptions{IdleTimeout: 20 * time.Millisecond})
	if mode != "copy" {
		t.Fatalf("mode = %q, want copy", mode)
	}
	if bytes != 0 {
		t.Fatalf("bytes = %d, want 0", bytes)
	}
	if err != ErrIdleTimeout {
		t.Fatalf("error = %v, want ErrIdleTimeout", err)
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
