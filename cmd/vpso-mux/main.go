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
	"sync/atomic"
	"syscall"
	"time"

	"github.com/Chunlion/VPS-Optimize/internal/mux"
	"golang.org/x/sys/unix"
)

const (
	maxPeekSize              = 16 * 1024
	statusJSONPath           = "/var/lib/vps-optimize/vpso-mux/status.json"
	statusFlushEvery         = 2 * time.Second
	statusWriteErrorLogEvery = 60 * time.Second
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
	BackendRetryAttempts uint64            `json:"backend_retry_attempts"`
	BackendRetrySuccess  uint64            `json:"backend_retry_success"`
	BackendRetryFailed   uint64            `json:"backend_retry_failed"`
	RouteHits            map[string]uint64 `json:"route_hits"`
	SpliceSuccess        uint64            `json:"splice_success"`
	CopyFallback         uint64            `json:"copy_fallback"`
	WhitelistBlocked     uint64            `json:"whitelist_blocked"`
	UnknownSNIBlocked    uint64            `json:"unknown_sni_blocked"`
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

// statusTracker 的计数器全部走 atomic，记录路径不抢锁；
// 锁只保留给状态文件写入（writeMu）和最近错误列表（errMu）。
type statusTracker struct {
	path         string
	listen       []string
	maxConn      int
	startTime    string
	writePayload func([]byte) error

	active    atomic.Int64
	mutations atomic.Uint64

	routeHits sync.Map // route name -> *atomic.Uint64

	total                       atomic.Uint64
	rejected                    atomic.Uint64
	dialErrors                  atomic.Uint64
	retryAttempts               atomic.Uint64
	retrySuccess                atomic.Uint64
	retryFailed                 atomic.Uint64
	spliceSuccess               atomic.Uint64
	copyFallback                atomic.Uint64
	whitelistBlocked            atomic.Uint64
	unknownSNIBlocked           atomic.Uint64
	noSNI                       atomic.Uint64
	peekErrors                  atomic.Uint64
	peekTimeouts                atomic.Uint64
	bytesClientToBackendCounter atomic.Uint64
	bytesBackendToClientCounter atomic.Uint64

	writeMu             sync.Mutex
	lastWrittenRevision uint64    // guarded by writeMu
	lastWriteErrorLog   time.Time // guarded by writeMu

	errMu        sync.Mutex
	recentErrors []statusError
}

type backendRetryStats struct {
	attempts uint64
	success  bool
	failed   bool
}

type backendDialFunc func(network, address string, timeout time.Duration) (net.Conn, error)

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

	if err := run(cfg, *configPath); err != nil {
		log.Fatalf("vpso-mux stopped: %v", err)
	}
}

// runtimeConfig 捆绑配置和派生时长，SIGHUP 重载时用 atomic.Pointer 整体换新。
// listen 和 max_connections 在启动时已固化到 listener/limiter，重载只影响新连接的路由行为。
type runtimeConfig struct {
	cfg *mux.Config
	d   mux.Durations
}

func newRuntimeConfig(cfg *mux.Config) (*runtimeConfig, error) {
	d, err := cfg.Durations()
	if err != nil {
		return nil, err
	}
	return &runtimeConfig{cfg: cfg, d: d}, nil
}

func reloadRuntimeConfig(path string, current *atomic.Pointer[runtimeConfig], logger *mux.Logger) {
	cfg, err := mux.LoadConfig(path)
	if err == nil {
		_, err = mux.ValidateConfig(cfg)
	}
	var d mux.Durations
	if err == nil {
		d, err = cfg.Durations()
	}
	if err != nil {
		logger.Emit("error", mux.LogEvent{Message: "config reload failed; keeping previous config", Error: err.Error()})
		return
	}
	current.Store(&runtimeConfig{cfg: cfg, d: d})
	logger.Emit("info", mux.LogEvent{Message: "config reloaded"})
}

func run(cfg *mux.Config, configPath string) error {
	rc, err := newRuntimeConfig(cfg)
	if err != nil {
		return err
	}
	var current atomic.Pointer[runtimeConfig]
	current.Store(rc)
	logger := mux.NewLogger(mux.LoggerOptions{
		Level:        cfg.Logging.Level,
		Format:       cfg.Logging.Format,
		File:         cfg.Logging.File,
		MaxSizeBytes: cfg.Logging.MaxSizeBytes,
		MaxBackups:   cfg.Logging.MaxBackups,
	})
	defer logger.Close()
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

	reloadSignals := make(chan os.Signal, 1)
	signal.Notify(reloadSignals, syscall.SIGHUP)
	defer signal.Stop(reloadSignals)
	var reloadWG sync.WaitGroup
	reloadWG.Add(1)
	go func() {
		defer reloadWG.Done()
		for {
			select {
			case <-ctx.Done():
				return
			case <-reloadSignals:
				reloadRuntimeConfig(configPath, &current, logger)
			}
		}
	}()
	defer reloadWG.Wait()

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
			acceptLoop(ctx, ln, &current, logger, status, limiter, &wg)
		}()
	}

	<-ctx.Done()
	for _, ln := range listeners {
		_ = ln.Close()
	}
	if !waitForShutdown(&wg, rc.d.Shutdown) {
		return fmt.Errorf("shutdown timeout after %s", rc.d.Shutdown)
	}
	return nil
}

func waitForShutdown(wg *sync.WaitGroup, timeout time.Duration) bool {
	if wg == nil {
		return true
	}
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()
	if timeout <= 0 {
		<-done
		return true
	}
	select {
	case <-done:
		return true
	case <-time.After(timeout):
		return false
	}
}

func newStatusTracker(listen []string, maxConnections int) *statusTracker {
	return &statusTracker{
		path:      statusJSONPath,
		listen:    append([]string(nil), listen...),
		maxConn:   maxConnections,
		startTime: time.Now().Format(time.RFC3339),
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
	s.write(true)
}

func (s *statusTracker) Flush() {
	s.write(false)
}

func (s *statusTracker) write(force bool) {
	if s == nil {
		return
	}
	s.writeMu.Lock()
	defer s.writeMu.Unlock()

	if !force && s.mutations.Load() == s.lastWrittenRevision {
		return
	}
	revision := s.mutations.Load()
	payload, err := json.MarshalIndent(s.snapshot(), "", "  ")
	if err == nil {
		payload = append(payload, '\n')
		if s.writePayload != nil {
			err = s.writePayload(payload)
		} else {
			err = writeStatusPayload(s.path, payload)
		}
	}
	if err != nil {
		s.logWriteErrorLocked(err)
		return
	}
	if revision > s.lastWrittenRevision {
		s.lastWrittenRevision = revision
	}
}

func (s *statusTracker) snapshot() runtimeStatus {
	active := s.active.Load()
	if active < 0 {
		active = 0
	}
	out := runtimeStatus{
		StartTime:            s.startTime,
		ListenAddresses:      s.listen,
		MaxConnections:       s.maxConn,
		ActiveConnections:    uint64(active),
		TotalConnections:     s.total.Load(),
		RejectedConnections:  s.rejected.Load(),
		BackendDialErrors:    s.dialErrors.Load(),
		BackendRetryAttempts: s.retryAttempts.Load(),
		BackendRetrySuccess:  s.retrySuccess.Load(),
		BackendRetryFailed:   s.retryFailed.Load(),
		RouteHits:            map[string]uint64{},
		SpliceSuccess:        s.spliceSuccess.Load(),
		CopyFallback:         s.copyFallback.Load(),
		WhitelistBlocked:     s.whitelistBlocked.Load(),
		UnknownSNIBlocked:    s.unknownSNIBlocked.Load(),
		NoSNI:                s.noSNI.Load(),
		PeekErrors:           s.peekErrors.Load(),
		PeekTimeouts:         s.peekTimeouts.Load(),
		BytesClientToBackend: s.bytesClientToBackendCounter.Load(),
		BytesBackendToClient: s.bytesBackendToClientCounter.Load(),
		UpdatedAt:            time.Now().Format(time.RFC3339),
	}
	s.routeHits.Range(func(key, value any) bool {
		out.RouteHits[key.(string)] = value.(*atomic.Uint64).Load()
		return true
	})
	s.errMu.Lock()
	out.RecentErrors = append([]statusError(nil), s.recentErrors...)
	s.errMu.Unlock()
	return out
}

func (s *statusTracker) RecordAccepted() {
	if s == nil {
		return
	}
	s.active.Add(1)
	s.mutations.Add(1)
}

func (s *statusTracker) RecordFinished() {
	if s == nil {
		return
	}
	s.active.Add(-1)
	s.mutations.Add(1)
}

func (s *statusTracker) RecordRejected(message string) {
	if s == nil {
		return
	}
	s.rejected.Add(1)
	s.addError(message, "", "")
	s.mutations.Add(1)
}

func (s *statusTracker) RecordPeekTimeout(message string) {
	if s == nil {
		return
	}
	s.rejected.Add(1)
	s.peekErrors.Add(1)
	s.peekTimeouts.Add(1)
	s.addError(message, "", "")
	s.mutations.Add(1)
}

func (s *statusTracker) RecordConnection(match mux.Match, sni, transferMode string, countCopyFallback bool, bytesClientToBackend, bytesBackendToClient int64, backendDialError, peekError bool, err error) {
	if s == nil {
		return
	}
	s.total.Add(1)
	routeName := match.RouteName
	if routeName == "" {
		routeName = "unknown"
	}
	s.recordRouteHit(routeName)
	if sni == "" {
		s.noSNI.Add(1)
	}
	if !match.Allowed || match.Blocked {
		if match.RouteName == "strict_sni_gate" {
			s.unknownSNIBlocked.Add(1)
		} else {
			s.whitelistBlocked.Add(1)
		}
		s.rejected.Add(1)
	}
	if backendDialError {
		s.dialErrors.Add(1)
	}
	if peekError {
		s.peekErrors.Add(1)
	}
	if bytesClientToBackend > 0 {
		s.bytesClientToBackendCounter.Add(uint64(bytesClientToBackend))
	}
	if bytesBackendToClient > 0 {
		s.bytesBackendToClientCounter.Add(uint64(bytesBackendToClient))
	}
	switch transferMode {
	case "splice":
		s.spliceSuccess.Add(1)
	case "copy":
		if countCopyFallback {
			s.copyFallback.Add(1)
		}
	}
	if err != nil {
		s.addError(err.Error(), sni, routeName)
	}
	s.mutations.Add(1)
}

func (s *statusTracker) RecordBackendRetryStats(stats backendRetryStats) {
	if s == nil || stats.attempts == 0 {
		return
	}
	s.retryAttempts.Add(stats.attempts)
	if stats.success {
		s.retrySuccess.Add(1)
	}
	if stats.failed {
		s.retryFailed.Add(1)
	}
	s.mutations.Add(1)
}

func (s *statusTracker) RecordError(message string) {
	if s == nil {
		return
	}
	s.addError(message, "", "")
	s.mutations.Add(1)
}

func (s *statusTracker) recordRouteHit(name string) {
	if value, ok := s.routeHits.Load(name); ok {
		value.(*atomic.Uint64).Add(1)
		return
	}
	actual, _ := s.routeHits.LoadOrStore(name, new(atomic.Uint64))
	actual.(*atomic.Uint64).Add(1)
}

func (s *statusTracker) addError(message, sni, routeName string) {
	if message == "" {
		return
	}
	s.errMu.Lock()
	defer s.errMu.Unlock()
	s.recentErrors = append(s.recentErrors, statusError{
		Time:      time.Now().Format(time.RFC3339),
		Message:   message,
		SNI:       sni,
		RouteName: routeName,
	})
	if len(s.recentErrors) > 10 {
		s.recentErrors = s.recentErrors[len(s.recentErrors)-10:]
	}
}

func writeStatusPayload(path string, payload []byte) error {
	if path == "" {
		return nil
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("create status directory %s: %w", dir, err)
	}
	tmp, err := os.CreateTemp(dir, "status.*.tmp")
	if err != nil {
		return fmt.Errorf("create temporary status file in %s: %w", dir, err)
	}
	tmpName := tmp.Name()
	_, err = tmp.Write(payload)
	if closeErr := tmp.Close(); err == nil {
		err = closeErr
	}
	if err == nil {
		err = os.Chmod(tmpName, 0644)
	}
	if err == nil {
		err = os.Rename(tmpName, path)
	}
	if err != nil {
		_ = os.Remove(tmpName)
		return fmt.Errorf("write status file %s: %w", path, err)
	}
	return nil
}

func (s *statusTracker) logWriteErrorLocked(err error) {
	if err == nil {
		return
	}
	now := time.Now()
	if !s.lastWriteErrorLog.IsZero() && now.Sub(s.lastWriteErrorLog) < statusWriteErrorLogEvery {
		return
	}
	s.lastWriteErrorLog = now
	log.Printf(`{"level":"error","message":"failed to write status json","path":%q,"error":%q}`, s.path, err.Error())
}

func acceptLoop(ctx context.Context, ln net.Listener, current *atomic.Pointer[runtimeConfig], logger *mux.Logger, status *statusTracker, limiter *connectionLimiter, wg *sync.WaitGroup) {
	// 对持续性 Accept 错误（如 fd 耗尽）指数退避，避免空转放大日志和状态锁压力。
	var acceptBackoff time.Duration
	for {
		conn, err := ln.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
			}
			logger.Emit("error", mux.LogEvent{Message: "accept failed", Error: err.Error()})
			status.RecordError("accept failed: " + err.Error())
			if acceptBackoff == 0 {
				acceptBackoff = 25 * time.Millisecond
			} else if acceptBackoff < time.Second {
				acceptBackoff *= 2
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(acceptBackoff):
			}
			continue
		}
		acceptBackoff = 0
		tcpConn, ok := conn.(*net.TCPConn)
		if !ok {
			_ = conn.Close()
			continue
		}
		_ = tcpConn.SetKeepAlive(true)
		_ = tcpConn.SetKeepAlivePeriod(time.Minute)
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
			rc := current.Load()
			handleConn(tcpConn, rc.cfg, rc.d, logger, status)
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

	sni, peekErr := peek(client, d.Peek)
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
	peekErrorForStatus := false

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
		if match.RouteName == "strict_sni_gate" {
			event.Error = "blocked by strict sni gate"
		} else {
			event.Error = "blocked by route whitelist"
		}
		logger.Emit("info", event)
		status.RecordConnection(match, sni, "", false, 0, 0, false, false, nil)
		return
	}
	if peekErr != nil && !errors.Is(peekErr, mux.ErrInvalidClientHello) && !errors.Is(peekErr, mux.ErrNoSNI) {
		event.Error = peekErr.Error()
		peekErrorForStatus = true
	}

	backend, retryStats, err := dialBackendWithRetry(match.Backend, d.Dial, cfg.BackendRetry.Count, d.BackendRetryDelay, dialBackend)
	status.RecordBackendRetryStats(retryStats)
	if err != nil {
		event.Error = err.Error()
		logger.Emit("error", event)
		status.RecordConnection(match, sni, "", false, 0, 0, true, peekErrorForStatus, err)
		return
	}
	defer backend.Close()

	if match.ProxyProtocol == "v1" {
		if err := writeProxyProtocolV1(backend, client); err != nil {
			event.Error = err.Error()
			logger.Emit("error", event)
			status.RecordConnection(match, sni, "", false, 0, 0, false, peekErrorForStatus, err)
			return
		}
	}

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

// dialBackend 是默认拨号函数：带 60s TCP keepalive，让静默断掉的死连接及时释放连接槽位。
func dialBackend(network, address string, timeout time.Duration) (net.Conn, error) {
	dialer := &net.Dialer{Timeout: timeout, KeepAlive: time.Minute}
	return dialer.Dial(network, address)
}

// writeProxyProtocolV1 在转发 ClientHello 前向 backend 发送 PROXY protocol v1 文本头，
// 让后端拿得到真实客户端 IP。
func writeProxyProtocolV1(backend net.Conn, client *net.TCPConn) error {
	remoteHost, remotePort, err := net.SplitHostPort(client.RemoteAddr().String())
	if err != nil {
		return err
	}
	localHost, localPort, err := net.SplitHostPort(client.LocalAddr().String())
	if err != nil {
		return err
	}
	family := "TCP4"
	if strings.Contains(remoteHost, ":") {
		family = "TCP6"
	}
	header := fmt.Sprintf("PROXY %s %s %s %s %s\r\n", family, remoteHost, localHost, remotePort, localPort)
	_, err = backend.Write([]byte(header))
	return err
}

func dialBackendWithRetry(backend string, dialTimeout time.Duration, retryCount int, retryDelay time.Duration, dial backendDialFunc) (net.Conn, backendRetryStats, error) {
	var stats backendRetryStats
	if dial == nil {
		dial = dialBackend
	}
	conn, err := dial("tcp", backend, dialTimeout)
	if err == nil {
		return conn, stats, nil
	}
	for i := 0; i < retryCount; i++ {
		stats.attempts++
		if retryDelay > 0 {
			time.Sleep(retryDelay)
		}
		conn, err = dial("tcp", backend, dialTimeout)
		if err == nil {
			stats.success = true
			return conn, stats, nil
		}
	}
	if stats.attempts > 0 {
		stats.failed = true
	}
	return nil, stats, err
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

// peek 缓冲统一取 16KB 池化块：MSG_PEEK 不消费数据，连接结束后整块归还，
// 免去每连接分配和 4K->16K 的逐级扩容。缓冲不逃出本函数，可安全复用。
var peekBufPool = sync.Pool{New: func() any {
	buf := make([]byte, maxPeekSize)
	return &buf
}}

// peek 读取完整 ClientHello 并返回其中的 SNI，不消费连接数据。
// needed 记录首次解析得到的完整 ClientHello 长度，未凑齐前跳过重复解析。
func peek(conn *net.TCPConn, timeout time.Duration) (string, error) {
	deadline := time.Now().Add(timeout)
	if timeout > 0 {
		if err := conn.SetReadDeadline(deadline); err != nil {
			return "", err
		}
		defer conn.SetReadDeadline(time.Time{})
	}

	bufPtr := peekBufPool.Get().(*[]byte)
	defer peekBufPool.Put(bufPtr)
	buf := *bufPtr
	lastN := -1
	needed := -1
	for {
		n, err := recvPeek(conn, buf)
		if err != nil {
			if isTimeoutError(err) {
				return "", errPeekTimeout
			}
			return "", err
		}
		if n == lastN {
			if timeout <= 0 {
				return "", nil
			}
			if !time.Now().Before(deadline) {
				return "", errPeekTimeout
			}
			time.Sleep(10 * time.Millisecond)
			continue
		}
		if needed >= 0 && n < needed {
			lastN = n
			continue
		}
		sni, parseErr := mux.ExtractSNI(buf[:n])
		if parseErr == nil {
			return sni, nil
		}
		if errors.Is(parseErr, mux.ErrNeedMore) {
			if n >= maxPeekSize {
				if timeout <= 0 {
					return "", nil
				}
				if !time.Now().Before(deadline) {
					return "", errPeekTimeout
				}
				lastN = n
				continue
			}
			needed = mux.ClientHelloNeeded(buf[:n])
			if needed <= n {
				// 多条 record 的 ClientHello 无法从头部预估总长，退化为每次有新数据再解析。
				needed = n + 1
			}
			lastN = n
			continue
		}
		// 无 SNI 或格式异常：照旧按无 SNI 处理，交给默认路由。
		return "", nil
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

func duplicateSocket(conn *net.TCPConn) (int, error) {
	raw, err := conn.SyscallConn()
	if err != nil {
		return -1, err
	}
	fd := -1
	var dupErr error
	if err := raw.Control(func(socket uintptr) {
		fd, dupErr = unix.FcntlInt(socket, unix.F_DUPFD_CLOEXEC, 0)
	}); err != nil {
		return -1, err
	}
	return fd, dupErr
}

// spliceUnavailable 记住本机内核/环境不支持 splice 的事实，
// 避免每条连接每个方向都重新走一遍 dup+pipe 建管再失败。
var spliceUnavailable atomic.Bool

func spliceCopy(dst, src *net.TCPConn, pipeSize int, idleTimeout time.Duration) (int64, error) {
	if spliceUnavailable.Load() {
		return 0, mux.ErrSpliceUnavailable
	}
	srcFD, err := duplicateSocket(src)
	if err != nil {
		return 0, errors.Join(mux.ErrSpliceUnavailable, err)
	}
	defer unix.Close(srcFD)
	dstFD, err := duplicateSocket(dst)
	if err != nil {
		return 0, errors.Join(mux.ErrSpliceUnavailable, err)
	}
	defer unix.Close(dstFD)
	var pipeFD [2]int
	if err := unix.Pipe2(pipeFD[:], unix.O_CLOEXEC|unix.O_NONBLOCK); err != nil {
		return 0, errors.Join(mux.ErrSpliceUnavailable, err)
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
			if total == 0 && (errors.Is(err, unix.EINVAL) || errors.Is(err, unix.ENOSYS) || errors.Is(err, unix.EOPNOTSUPP)) {
				spliceUnavailable.Store(true)
				return 0, errors.Join(mux.ErrSpliceUnavailable, err)
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
	timeoutMs := int(idleTimeout / time.Millisecond)
	if idleTimeout%time.Millisecond != 0 {
		timeoutMs++
	}
	if timeoutMs < 1 {
		timeoutMs = 1
	}
	if idleTimeout <= 0 {
		timeoutMs = -1
	}
	var pollFds [1]unix.PollFd
	pollFds[0] = unix.PollFd{Fd: int32(fd), Events: events}
	for {
		n, err := unix.Poll(pollFds[:], timeoutMs)
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
