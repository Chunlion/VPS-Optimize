//go:build linux

package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/netip"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/Chunlion/VPS-Optimize/internal/mux"
	"golang.org/x/sys/unix"
)

const (
	initialPeekSize  = 4096
	maxPeekSize      = 16 * 1024
	statusJSONPath   = "/var/lib/vps-optimize/vpso-mux/status.json"
	statusFlushEvery = 2 * time.Second
)

var errPeekTimeout = errors.New("peek timeout before complete ClientHello")

type runtimeStatus struct {
	StartTime            string            `json:"start_time"`
	ListenAddresses      []string          `json:"listen_addresses"`
	MaxConnections       int               `json:"max_connections"`
	ActiveConnections    uint64            `json:"active_connections"`
	TotalConnections     uint64            `json:"total_connections"`
	RejectedConnections  uint64            `json:"rejected_connections"`
	BackendDialErrors    uint64            `json:"backend_dial_errors"`
	RouteHits            map[string]uint64 `json:"route_hits"`
	SpliceSuccess        uint64            `json:"splice_success"`
	CopyFallback         uint64            `json:"copy_fallback"`
	WhitelistBlocked     uint64            `json:"whitelist_blocked"`
	NoSNI                uint64            `json:"no_sni"`
	PeekErrors           uint64            `json:"peek_errors"`
	PeekTimeouts         uint64            `json:"peek_timeouts"`
	BytesClientToBackend uint64            `json:"bytes_client_to_backend"`
	BytesBackendToClient uint64            `json:"bytes_backend_to_client"`
	RecentErrors         []statusError     `json:"recent_errors,omitempty"`
	UpdatedAt            string            `json:"updated_at"`
}

type statusError struct {
	Time      string `json:"time"`
	Message   string `json:"message"`
	SNI       string `json:"sni,omitempty"`
	RouteName string `json:"route_name,omitempty"`
}

type statusTracker struct {
	mu    sync.Mutex
	path  string
	data  runtimeStatus
	dirty bool
}

type connectionLimiter struct {
	sem chan struct{}
}

func newConnectionLimiter(max int) *connectionLimiter {
	if max <= 0 {
		return nil
	}
	return &connectionLimiter{sem: make(chan struct{}, max)}
}

func (l *connectionLimiter) Acquire() bool {
	if l == nil {
		return true
	}
	select {
	case l.sem <- struct{}{}:
		return true
	default:
		return false
	}
}

func (l *connectionLimiter) Release() {
	if l == nil {
		return
	}
	select {
	case <-l.sem:
	default:
	}
}

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
	status := newStatusTracker(cfg.Listen.TCP, cfg.Limits.MaxConnections)
	limiter := newConnectionLimiter(cfg.Limits.MaxConnections)
	var statusWG sync.WaitGroup
	status.Start(ctx, statusFlushEvery, &statusWG)
	defer func() {
		stop()
		statusWG.Wait()
		status.Write()
	}()

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
	status.Write()

	var wg sync.WaitGroup
	for _, ln := range listeners {
		ln := ln
		wg.Add(1)
		go func() {
			defer wg.Done()
			acceptLoop(ctx, ln, cfg, durations, logger, status, limiter, &wg)
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

func newStatusTracker(listen []string, maxConnections int) *statusTracker {
	listenCopy := append([]string(nil), listen...)
	now := time.Now().Format(time.RFC3339)
	return &statusTracker{
		path: statusJSONPath,
		data: runtimeStatus{
			StartTime:       now,
			ListenAddresses: listenCopy,
			MaxConnections:  maxConnections,
			RouteHits:       map[string]uint64{},
			UpdatedAt:       now,
		},
	}
}

func (s *statusTracker) Start(ctx context.Context, interval time.Duration, wg *sync.WaitGroup) {
	if s == nil || wg == nil || interval <= 0 {
		return
	}
	wg.Add(1)
	go func() {
		defer wg.Done()
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				s.Flush()
			case <-ctx.Done():
				s.Flush()
				return
			}
		}
	}()
}

func (s *statusTracker) Write() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.writeLocked()
	s.dirty = false
}

func (s *statusTracker) Flush() {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.dirty {
		return
	}
	s.writeLocked()
	s.dirty = false
}

func (s *statusTracker) markDirtyLocked() {
	s.dirty = true
}

func (s *statusTracker) RecordAccepted() {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data.ActiveConnections++
	s.markDirtyLocked()
}

func (s *statusTracker) RecordFinished() {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.data.ActiveConnections > 0 {
		s.data.ActiveConnections--
	}
	s.markDirtyLocked()
}

func (s *statusTracker) RecordRejected(message string) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data.RejectedConnections++
	s.addErrorLocked(message, "", "")
	s.markDirtyLocked()
}

func (s *statusTracker) RecordPeekTimeout(message string) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data.RejectedConnections++
	s.data.PeekErrors++
	s.data.PeekTimeouts++
	s.addErrorLocked(message, "", "")
	s.markDirtyLocked()
}

func (s *statusTracker) RecordConnection(match mux.Match, sni, transferMode string, countCopyFallback bool, bytesClientToBackend, bytesBackendToClient int64, backendDialError, peekError bool, err error) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	s.data.TotalConnections++
	routeName := match.RouteName
	if routeName == "" {
		routeName = "unknown"
	}
	s.data.RouteHits[routeName]++
	if sni == "" {
		s.data.NoSNI++
	}
	if !match.Allowed || match.Blocked {
		s.data.WhitelistBlocked++
		s.data.RejectedConnections++
	}
	if backendDialError {
		s.data.BackendDialErrors++
	}
	if peekError {
		s.data.PeekErrors++
	}
	if bytesClientToBackend > 0 {
		s.data.BytesClientToBackend += uint64(bytesClientToBackend)
	}
	if bytesBackendToClient > 0 {
		s.data.BytesBackendToClient += uint64(bytesBackendToClient)
	}
	switch transferMode {
	case "splice":
		s.data.SpliceSuccess++
	case "copy":
		if countCopyFallback {
			s.data.CopyFallback++
		}
	}
	if err != nil {
		s.addErrorLocked(err.Error(), sni, routeName)
	}
	s.markDirtyLocked()
}

func (s *statusTracker) RecordError(message string) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.addErrorLocked(message, "", "")
	s.markDirtyLocked()
}

func (s *statusTracker) addErrorLocked(message, sni, routeName string) {
	if message == "" {
		return
	}
	s.data.RecentErrors = append(s.data.RecentErrors, statusError{
		Time:      time.Now().Format(time.RFC3339),
		Message:   message,
		SNI:       sni,
		RouteName: routeName,
	})
	if len(s.data.RecentErrors) > 10 {
		s.data.RecentErrors = s.data.RecentErrors[len(s.data.RecentErrors)-10:]
	}
}

func (s *statusTracker) writeLocked() {
	if s == nil || s.path == "" {
		return
	}
	s.data.UpdatedAt = time.Now().Format(time.RFC3339)
	payload, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		return
	}
	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return
	}
	tmp, err := os.CreateTemp(dir, "status.*.tmp")
	if err != nil {
		return
	}
	tmpName := tmp.Name()
	if _, err = tmp.Write(payload); err == nil {
		_, err = tmp.Write([]byte("\n"))
	}
	if closeErr := tmp.Close(); err == nil {
		err = closeErr
	}
	if err == nil {
		err = os.Chmod(tmpName, 0644)
	}
	if err == nil {
		err = os.Rename(tmpName, s.path)
	}
	if err != nil {
		_ = os.Remove(tmpName)
	}
}

func acceptLoop(ctx context.Context, ln net.Listener, cfg *mux.Config, d mux.Durations, logger *mux.Logger, status *statusTracker, limiter *connectionLimiter, wg *sync.WaitGroup) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				logger.Emit("error", mux.LogEvent{Message: "accept failed", Error: err.Error()})
				status.RecordError("accept failed: " + err.Error())
				continue
			}
		}
		tcpConn, ok := conn.(*net.TCPConn)
		if !ok {
			_ = conn.Close()
			continue
		}
		if !limiter.Acquire() {
			allowed := false
			logger.Emit("warn", mux.LogEvent{
				ClientIP: remoteIP(tcpConn.RemoteAddr()),
				Allowed:  &allowed,
				Blocked:  true,
				Error:    "connection limit reached",
			})
			status.RecordRejected("connection limit reached")
			_ = tcpConn.Close()
			continue
		}
		status.RecordAccepted()
		wg.Add(1)
		go func() {
			defer wg.Done()
			defer limiter.Release()
			defer status.RecordFinished()
			handleConn(tcpConn, cfg, d, logger, status)
		}()
	}
}

func handleConn(client *net.TCPConn, cfg *mux.Config, d mux.Durations, logger *mux.Logger, status *statusTracker) {
	defer client.Close()
	clientIP := remoteIP(client.RemoteAddr())
	clientAddr := netip.Addr{}
	if clientIP != "" {
		if parsed, err := netip.ParseAddr(clientIP); err == nil {
			clientAddr = parsed
		}
	}

	peeked, peekErr := peek(client, d.Peek)
	if errors.Is(peekErr, errPeekTimeout) {
		allowed := false
		logger.Emit("warn", mux.LogEvent{
			ClientIP: clientIP,
			Allowed:  &allowed,
			Blocked:  true,
			Error:    peekErr.Error(),
			Message:  "closing slow ClientHello",
		})
		status.RecordPeekTimeout(peekErr.Error())
		return
	}
	sni := ""
	peekErrorForStatus := false
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
		status.RecordConnection(match, sni, "", false, 0, 0, false, false, nil)
		return
	}
	if peekErr != nil && !errors.Is(peekErr, mux.ErrInvalidClientHello) && !errors.Is(peekErr, mux.ErrNoSNI) {
		event.Error = peekErr.Error()
		peekErrorForStatus = true
	}

	backend, err := net.DialTimeout("tcp", match.Backend, d.Dial)
	if err != nil {
		event.Error = err.Error()
		logger.Emit("error", event)
		status.RecordConnection(match, sni, "", false, 0, 0, true, peekErrorForStatus, err)
		return
	}
	defer backend.Close()

	mode, bytesClientToBackend, bytesBackendToClient, err := mux.ProxyBidirectional(client, backend, mux.TransferOptions{
		SpliceEnabled:  cfg.Splice.Enabled,
		FallbackToCopy: cfg.Splice.FallbackToCopy,
		PipeSize:       cfg.Splice.PipeSize,
		IdleTimeout:    d.Idle,
		SpliceCopy:     spliceCopy,
	})
	event.TransferMode = mode
	var statusErr error
	if event.Error != "" {
		statusErr = errors.New(event.Error)
	}
	if err != nil && !errors.Is(err, io.EOF) && !strings.Contains(err.Error(), "use of closed network connection") {
		event.Error = err.Error()
		logger.Emit("error", event)
		status.RecordConnection(match, sni, mode, cfg.Splice.Enabled && cfg.Splice.FallbackToCopy, bytesClientToBackend, bytesBackendToClient, false, peekErrorForStatus, err)
		return
	}
	logger.Emit("info", event)
	status.RecordConnection(match, sni, mode, cfg.Splice.Enabled && cfg.Splice.FallbackToCopy, bytesClientToBackend, bytesBackendToClient, false, peekErrorForStatus, statusErr)
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
			if isTimeoutError(err) {
				return nil, errPeekTimeout
			}
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
			if timeout <= 0 {
				return buf[:n], nil
			}
			if !time.Now().Before(deadline) {
				return buf[:n], errPeekTimeout
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

func isTimeoutError(err error) bool {
	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
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

func spliceCopy(dst, src *net.TCPConn, pipeSize int, idleTimeout time.Duration) (int64, error) {
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
	const spliceFlags = unix.SPLICE_F_MOVE | unix.SPLICE_F_NONBLOCK
	for {
		if err := waitFD(srcFD, unix.POLLIN|unix.POLLHUP|unix.POLLERR, idleTimeout); err != nil {
			return total, err
		}
		n, err := unix.Splice(srcFD, nil, pipeFD[1], nil, chunk, spliceFlags)
		if err != nil {
			if errors.Is(err, unix.EINTR) {
				continue
			}
			if errors.Is(err, unix.EAGAIN) || errors.Is(err, unix.EWOULDBLOCK) {
				continue
			}
			return total, err
		}
		if n == 0 {
			return total, nil
		}
		remaining := n
		for remaining > 0 {
			if err := waitFD(dstFD, unix.POLLOUT|unix.POLLHUP|unix.POLLERR, idleTimeout); err != nil {
				return total, err
			}
			written, err := unix.Splice(pipeFD[0], nil, dstFD, nil, int(remaining), spliceFlags)
			if err != nil {
				if errors.Is(err, unix.EINTR) {
					continue
				}
				if errors.Is(err, unix.EAGAIN) || errors.Is(err, unix.EWOULDBLOCK) {
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

func waitFD(fd int, events int16, idleTimeout time.Duration) error {
	if idleTimeout <= 0 {
		return nil
	}
	timeoutMs := int(idleTimeout / time.Millisecond)
	if idleTimeout%time.Millisecond != 0 {
		timeoutMs++
	}
	if timeoutMs < 1 {
		timeoutMs = 1
	}
	pollFds := []unix.PollFd{{Fd: int32(fd), Events: events}}
	for {
		n, err := unix.Poll(pollFds, timeoutMs)
		if errors.Is(err, unix.EINTR) {
			continue
		}
		if err != nil {
			return err
		}
		if n == 0 {
			return mux.ErrIdleTimeout
		}
		return nil
	}
}

func init() {
	log.SetOutput(os.Stdout)
	log.SetFlags(0)
}
