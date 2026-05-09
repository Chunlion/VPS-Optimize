package mux

import (
	"errors"
	"io"
	"net"
	"sync"
	"time"
)

var ErrSpliceUnavailable = errors.New("splice unavailable")

type TransferOptions struct {
	SpliceEnabled  bool
	FallbackToCopy bool
	PipeSize       int
	IdleTimeout    time.Duration
	SpliceCopy     func(dst, src *net.TCPConn, pipeSize int) (int64, error)
}

type TransferResult struct {
	Mode string
	Err  error
}

func ProxyBidirectional(client, backend net.Conn, opts TransferOptions) (string, error) {
	var wg sync.WaitGroup
	results := make(chan TransferResult, 2)
	wg.Add(2)
	go func() {
		defer wg.Done()
		mode, err := copyDirection(backend, client, opts)
		closeWrite(backend)
		results <- TransferResult{Mode: mode, Err: err}
	}()
	go func() {
		defer wg.Done()
		mode, err := copyDirection(client, backend, opts)
		closeWrite(client)
		results <- TransferResult{Mode: mode, Err: err}
	}()
	wg.Wait()
	close(results)

	mode := "copy"
	var finalErr error
	for result := range results {
		if result.Mode == "splice" {
			mode = "splice"
		}
		if result.Err != nil && !errors.Is(result.Err, io.EOF) {
			finalErr = result.Err
		}
	}
	return mode, finalErr
}

func copyDirection(dst, src net.Conn, opts TransferOptions) (string, error) {
	if opts.SpliceEnabled && opts.SpliceCopy != nil {
		dstTCP, dstOK := dst.(*net.TCPConn)
		srcTCP, srcOK := src.(*net.TCPConn)
		if dstOK && srcOK {
			if _, err := opts.SpliceCopy(dstTCP, srcTCP, opts.PipeSize); err == nil {
				return "splice", nil
			} else if !opts.FallbackToCopy {
				return "splice", err
			}
		}
	}
	err := copyWithIdleDeadline(dst, src, opts.IdleTimeout)
	return "copy", err
}

func copyWithIdleDeadline(dst, src net.Conn, idle time.Duration) error {
	buf := make([]byte, 32*1024)
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
				return ew
			}
			if nw != nr {
				return io.ErrShortWrite
			}
		}
		if er != nil {
			if errors.Is(er, io.EOF) {
				return nil
			}
			return er
		}
	}
}

func closeWrite(conn net.Conn) {
	if tcp, ok := conn.(*net.TCPConn); ok {
		_ = tcp.CloseWrite()
		return
	}
	_ = conn.Close()
}
