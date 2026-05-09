//go:build linux

package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/netip"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/Chunlion/VPS-Optimize/internal/mux"
	"golang.org/x/sys/unix"
)

const (
	initialPeekSize = 4096
	maxPeekSize     = 16 * 1024
)

func main() {
	configPath := flag.String("config", "/etc/vps-optimize/vpso-mux.yaml", "path to vpso-mux yaml config")
	checkOnly := flag.Bool("check", false, "validate config and exit")
	flag.Parse()

	cfg, err := mux.LoadConfig(*configPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	warnings, err := mux.ValidateConfig(cfg)
	for _, warning := range warnings {
		log.Printf("warning: %s", warning)
	}
	if err != nil {
		log.Fatalf("validate config: %v", err)
	}
	if *checkOnly {
		log.Printf("config ok: %s", *configPath)
		return
	}

	if err := run(cfg); err != nil {
		log.Fatalf("vpso-mux stopped: %v", err)
	}
}

func run(cfg *mux.Config) error {
	durations, err := cfg.Durations()
	if err != nil {
		return err
	}
	logger := mux.NewLogger()
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	var listeners []net.Listener
	for _, addr := range cfg.Listen.TCP {
		ln, err := net.Listen("tcp", addr)
		if err != nil {
			for _, opened := range listeners {
				_ = opened.Close()
			}
			return fmt.Errorf("listen %s: %w", addr, err)
		}
		listeners = append(listeners, ln)
		logger.Emit("info", mux.LogEvent{Message: "listening", Backend: addr})
	}

	var wg sync.WaitGroup
	for _, ln := range listeners {
		ln := ln
		wg.Add(1)
		go func() {
			defer wg.Done()
			acceptLoop(ctx, ln, cfg, durations, logger, &wg)
		}()
	}

	<-ctx.Done()
	for _, ln := range listeners {
		_ = ln.Close()
	}
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(durations.Shutdown):
		return fmt.Errorf("shutdown timeout after %s", durations.Shutdown)
	}
	return nil
}

func acceptLoop(ctx context.Context, ln net.Listener, cfg *mux.Config, d mux.Durations, logger *mux.Logger, wg *sync.WaitGroup) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				logger.Emit("error", mux.LogEvent{Message: "accept failed", Error: err.Error()})
				continue
			}
		}
		tcpConn, ok := conn.(*net.TCPConn)
		if !ok {
			_ = conn.Close()
			continue
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			handleConn(tcpConn, cfg, d, logger)
		}()
	}
}

func handleConn(client *net.TCPConn, cfg *mux.Config, d mux.Durations, logger *mux.Logger) {
	defer client.Close()
	clientIP := remoteIP(client.RemoteAddr())
	clientAddr := netip.Addr{}
	if clientIP != "" {
		if parsed, err := netip.ParseAddr(clientIP); err == nil {
			clientAddr = parsed
		}
	}

	peeked, peekErr := peek(client, d.Peek)
	sni := ""
	if peekErr == nil {
		parsedSNI, err := mux.ExtractSNI(peeked)
		if err == nil {
			sni = parsedSNI
		} else if !errors.Is(err, mux.ErrNoSNI) && !errors.Is(err, mux.ErrInvalidClientHello) && !errors.Is(err, mux.ErrNeedMore) {
			peekErr = err
		}
	}

	match := mux.MatchRoute(cfg, sni, clientAddr)
	allowed := match.Allowed
	event := mux.LogEvent{
		ClientIP:  clientIP,
		SNI:       sni,
		Backend:   match.Backend,
		RouteName: match.RouteName,
		Allowed:   &allowed,
		Blocked:   match.Blocked,
	}

	if !match.Allowed && match.Backend == "" {
		event.Error = "blocked by route whitelist"
		logger.Emit("info", event)
		return
	}
	if peekErr != nil && !errors.Is(peekErr, mux.ErrInvalidClientHello) && !errors.Is(peekErr, mux.ErrNoSNI) {
		event.Error = peekErr.Error()
	}

	backend, err := net.DialTimeout("tcp", match.Backend, d.Dial)
	if err != nil {
		event.Error = err.Error()
		logger.Emit("error", event)
		return
	}
	defer backend.Close()

	mode, err := mux.ProxyBidirectional(client, backend, mux.TransferOptions{
		SpliceEnabled:  cfg.Splice.Enabled,
		FallbackToCopy: cfg.Splice.FallbackToCopy,
		PipeSize:       cfg.Splice.PipeSize,
		IdleTimeout:    d.Idle,
		SpliceCopy:     spliceCopy,
	})
	event.TransferMode = mode
	if err != nil && !errors.Is(err, io.EOF) && !strings.Contains(err.Error(), "use of closed network connection") {
		event.Error = err.Error()
		logger.Emit("error", event)
		return
	}
	logger.Emit("info", event)
}

func remoteIP(addr net.Addr) string {
	if addr == nil {
		return ""
	}
	host, _, err := net.SplitHostPort(addr.String())
	if err != nil {
		return addr.String()
	}
	return strings.Trim(host, "[]")
}

func peek(conn *net.TCPConn, timeout time.Duration) ([]byte, error) {
	deadline := time.Now().Add(timeout)
	if timeout > 0 {
		if err := conn.SetReadDeadline(deadline); err != nil {
			return nil, err
		}
		defer conn.SetReadDeadline(time.Time{})
	}

	size := initialPeekSize
	lastN := -1
	for {
		buf := make([]byte, size)
		n, err := recvPeek(conn, buf)
		if err != nil {
			return nil, err
		}
		if _, parseErr := mux.ExtractSNI(buf[:n]); errors.Is(parseErr, mux.ErrNeedMore) {
			if size < maxPeekSize {
				size *= 2
				if size > maxPeekSize {
					size = maxPeekSize
				}
				lastN = n
				continue
			}
			if timeout <= 0 || !time.Now().Before(deadline) {
				return buf[:n], nil
			}
			if n == lastN {
				time.Sleep(10 * time.Millisecond)
			}
			lastN = n
			continue
		}
		return buf[:n], nil
	}
}

func recvPeek(conn *net.TCPConn, buf []byte) (int, error) {
	raw, err := conn.SyscallConn()
	if err != nil {
		return 0, err
	}
	var n int
	var opErr error
	err = raw.Read(func(fd uintptr) bool {
		n, _, opErr = unix.Recvfrom(int(fd), buf, unix.MSG_PEEK)
		if errors.Is(opErr, unix.EAGAIN) || errors.Is(opErr, unix.EWOULDBLOCK) || errors.Is(opErr, unix.EINTR) {
			return false
		}
		return true
	})
	if err != nil {
		return 0, err
	}
	if opErr != nil {
		return 0, opErr
	}
	if n == 0 {
		return 0, io.EOF
	}
	return n, nil
}

func spliceCopy(dst, src *net.TCPConn, pipeSize int) (int64, error) {
	srcFile, err := src.File()
	if err != nil {
		return 0, err
	}
	defer srcFile.Close()
	dstFile, err := dst.File()
	if err != nil {
		return 0, err
	}
	defer dstFile.Close()

	srcFD := int(srcFile.Fd())
	dstFD := int(dstFile.Fd())
	var pipeFD [2]int
	if err := unix.Pipe2(pipeFD[:], unix.O_CLOEXEC); err != nil {
		return 0, err
	}
	defer unix.Close(pipeFD[0])
	defer unix.Close(pipeFD[1])
	if pipeSize > 0 {
		_, _ = unix.FcntlInt(uintptr(pipeFD[0]), unix.F_SETPIPE_SZ, pipeSize)
	}

	var total int64
	const chunk = 256 * 1024
	for {
		n, err := unix.Splice(srcFD, nil, pipeFD[1], nil, chunk, unix.SPLICE_F_MOVE)
		if err != nil {
			if errors.Is(err, unix.EINTR) || errors.Is(err, unix.EAGAIN) {
				continue
			}
			return total, err
		}
		if n == 0 {
			return total, nil
		}
		remaining := n
		for remaining > 0 {
			written, err := unix.Splice(pipeFD[0], nil, dstFD, nil, remaining, unix.SPLICE_F_MOVE)
			if err != nil {
				if errors.Is(err, unix.EINTR) || errors.Is(err, unix.EAGAIN) {
					continue
				}
				return total, err
			}
			if written == 0 {
				return total, io.ErrShortWrite
			}
			remaining -= written
			total += int64(written)
		}
	}
}

func init() {
	log.SetOutput(os.Stdout)
	log.SetFlags(0)
}
