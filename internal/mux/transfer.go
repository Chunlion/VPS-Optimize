package mux

import (
	"errors"
	"io"
	"net"
	"sync"
	"time"
)

var (
	ErrSpliceUnavailable = errors.New("splice unavailable")
	ErrIdleTimeout       = errors.New("idle timeout")
)

type TransferOptions struct {
	SpliceEnabled  bool
	FallbackToCopy bool
	PipeSize       int
	IdleTimeout    time.Duration
	SpliceCopy     func(dst, src *net.TCPConn, pipeSize int, idleTimeout time.Duration) (int64, error)
}

type TransferResult struct {
	Direction string
	Mode      string
	Bytes     int64
	Err       error
}

func ProxyBidirectional(client, backend net.Conn, opts TransferOptions) (string, int64, int64, error) {
	var wg sync.WaitGroup
	results := make(chan TransferResult, 2)
	wg.Add(2)
	go func() {
		defer wg.Done()
		mode, bytes, err := copyDirection(backend, client, opts)
		closeWrite(backend)
		results <- TransferResult{Direction: "client_to_backend", Mode: mode, Bytes: bytes, Err: err}
	}()
	go func() {
		defer wg.Done()
		mode, bytes, err := copyDirection(client, backend, opts)
		closeWrite(client)
		results <- TransferResult{Direction: "backend_to_client", Mode: mode, Bytes: bytes, Err: err}
	}()
	wg.Wait()
	close(results)

	mode := "copy"
	var clientToBackend int64
	var backendToClient int64
	var finalErr error
	for result := range results {
		if result.Mode == "splice" {
			mode = "splice"
		}
		if result.Direction == "client_to_backend" {
			clientToBackend = result.Bytes
		} else {
			backendToClient = result.Bytes
		}
		if result.Err != nil && !errors.Is(result.Err, io.EOF) && !errors.Is(result.Err, ErrIdleTimeout) {
			finalErr = result.Err
		}
	}
	return mode, clientToBackend, backendToClient, finalErr
}

func copyDirection(dst, src net.Conn, opts TransferOptions) (string, int64, error) {
	if opts.SpliceEnabled && opts.SpliceCopy != nil {
		dstTCP, dstOK := dst.(*net.TCPConn)
		srcTCP, srcOK := src.(*net.TCPConn)
		if dstOK && srcOK {
			if bytes, err := opts.SpliceCopy(dstTCP, srcTCP, opts.PipeSize, opts.IdleTimeout); err == nil {
				return "splice", bytes, nil
			} else if !opts.FallbackToCopy {
				return "splice", bytes, err
			}
		}
	}
	bytes, err := copyWithIdleDeadline(dst, src, opts.IdleTimeout)
	return "copy", bytes, err
}

func copyWithIdleDeadline(dst, src net.Conn, idle time.Duration) (int64, error) {
	buf := make([]byte, 32*1024)
	var total int64
	for {
		if idle > 0 {
			_ = src.SetReadDeadline(time.Now().Add(idle))
		}
		nr, er := src.Read(buf)
		if nr > 0 {
			if idle > 0 {
				_ = dst.SetWriteDeadline(time.Now().Add(idle))
			}
			nw, ew := dst.Write(buf[:nr])
			if ew != nil {
				return total, ew
			}
			if nw != nr {
				return total, io.ErrShortWrite
			}
			total += int64(nw)
		}
		if er != nil {
			if errors.Is(er, io.EOF) {
				return total, nil
			}
			if isTimeoutError(er) {
				return total, ErrIdleTimeout
			}
			return total, er
		}
	}
}

func isTimeoutError(err error) bool {
	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
}

func closeWrite(conn net.Conn) {
	if tcp, ok := conn.(*net.TCPConn); ok {
		_ = tcp.CloseWrite()
		return
	}
	_ = conn.Close()
}
