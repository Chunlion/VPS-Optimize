package mux

import (
	"bytes"
	"fmt"
	"net"
	"os"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Listen struct {
		TCP []string `yaml:"tcp"`
	} `yaml:"listen"`
	Timeouts struct {
		Peek     string `yaml:"peek"`
		Dial     string `yaml:"dial"`
		Idle     string `yaml:"idle"`
		Shutdown string `yaml:"shutdown"`
	} `yaml:"timeouts"`
	BackendRetry struct {
		Count int    `yaml:"count"`
		Delay string `yaml:"delay"`
	} `yaml:"backend_retry"`
	Splice struct {
		Enabled        bool `yaml:"enabled"`
		PipeSize       int  `yaml:"pipe_size"`
		FallbackToCopy bool `yaml:"fallback_to_copy"`
	} `yaml:"splice"`
	Limits struct {
		MaxConnections int `yaml:"max_connections"`
	} `yaml:"limits"`
	DefaultBackend string  `yaml:"default_backend"`
	Routes         []Route `yaml:"routes"`
	Logging        struct {
		Level        string `yaml:"level"`
		Format       string `yaml:"format"`
		File         string `yaml:"file"`
		MaxSizeBytes int64  `yaml:"max_size_bytes"`
		MaxBackups   int    `yaml:"max_backups"`
	} `yaml:"logging"`

	routeIndex *routeIndex
}

type Durations struct {
	Peek              time.Duration
	Dial              time.Duration
	Idle              time.Duration
	Shutdown          time.Duration
	BackendRetryDelay time.Duration
}

func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	cfg := DefaultConfig()
	decoder := yaml.NewDecoder(bytes.NewReader(data))
	decoder.KnownFields(true)
	if err := decoder.Decode(cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

func DefaultConfig() *Config {
	cfg := &Config{}
	cfg.Timeouts.Peek = "3s"
	cfg.Timeouts.Dial = "5s"
	cfg.Timeouts.Idle = "300s"
	cfg.Timeouts.Shutdown = "10s"
	cfg.BackendRetry.Count = 0
	cfg.BackendRetry.Delay = "200ms"
	cfg.Splice.Enabled = true
	cfg.Splice.PipeSize = 1048576
	cfg.Splice.FallbackToCopy = true
	cfg.Limits.MaxConnections = 4096
	cfg.Logging.Level = "info"
	cfg.Logging.Format = "json"
	cfg.Logging.MaxSizeBytes = 5 * 1024 * 1024
	cfg.Logging.MaxBackups = 3
	return cfg
}

func (c *Config) Durations() (Durations, error) {
	var out Durations
	var err error
	if out.Peek, err = parseDurationDefault(c.Timeouts.Peek, 3*time.Second); err != nil {
		return out, fmt.Errorf("timeouts.peek: %w", err)
	}
	if out.Dial, err = parseDurationDefault(c.Timeouts.Dial, 5*time.Second); err != nil {
		return out, fmt.Errorf("timeouts.dial: %w", err)
	}
	if out.Idle, err = parseDurationDefault(c.Timeouts.Idle, 300*time.Second); err != nil {
		return out, fmt.Errorf("timeouts.idle: %w", err)
	}
	if out.Shutdown, err = parseDurationDefault(c.Timeouts.Shutdown, 10*time.Second); err != nil {
		return out, fmt.Errorf("timeouts.shutdown: %w", err)
	}
	if out.BackendRetryDelay, err = parseDurationDefault(c.BackendRetry.Delay, 200*time.Millisecond); err != nil {
		return out, fmt.Errorf("backend_retry.delay: %w", err)
	}
	return out, nil
}

func parseDurationDefault(value string, fallback time.Duration) (time.Duration, error) {
	if strings.TrimSpace(value) == "" {
		return fallback, nil
	}
	return time.ParseDuration(value)
}

func ValidateConfig(c *Config) ([]string, error) {
	if c == nil {
		return nil, fmt.Errorf("config is nil")
	}
	var warnings []string
	if len(c.Listen.TCP) == 0 {
		return warnings, fmt.Errorf("listen.tcp must not be empty")
	}
	for _, addr := range c.Listen.TCP {
		if err := validateBackendAddress(addr); err != nil {
			return warnings, fmt.Errorf("listen.tcp %q: %w", addr, err)
		}
	}
	if err := validateBackendAddress(c.DefaultBackend); err != nil {
		return warnings, fmt.Errorf("default_backend: %w", err)
	}
	if _, err := c.Durations(); err != nil {
		return warnings, err
	}
	if c.Splice.PipeSize < 0 {
		return warnings, fmt.Errorf("splice.pipe_size must be >= 0")
	}
	if c.Limits.MaxConnections < 0 {
		return warnings, fmt.Errorf("limits.max_connections must be >= 0")
	}
	if c.BackendRetry.Count < 0 {
		return warnings, fmt.Errorf("backend_retry.count must be >= 0")
	}
	if c.Logging.MaxSizeBytes < 0 {
		return warnings, fmt.Errorf("logging.max_size_bytes must be >= 0")
	}
	if c.Logging.MaxBackups < 0 {
		return warnings, fmt.Errorf("logging.max_backups must be >= 0")
	}
	if err := normalizeEnumDefault(&c.Logging.Level, "info", map[string]struct{}{"debug": {}, "info": {}, "warn": {}, "error": {}}); err != nil {
		return warnings, fmt.Errorf("logging.level: %w", err)
	}
	if err := normalizeEnumDefault(&c.Logging.Format, "json", map[string]struct{}{"json": {}, "text": {}}); err != nil {
		return warnings, fmt.Errorf("logging.format: %w", err)
	}

	seen := map[string]string{}
	routeNames := map[string]int{}
	for i := range c.Routes {
		route := &c.Routes[i]
		route.Name = strings.TrimSpace(route.Name)
		if route.Name == "" {
			return warnings, fmt.Errorf("routes[%d].name must not be empty", i)
		}
		if prev, ok := routeNames[route.Name]; ok {
			return warnings, fmt.Errorf("duplicate route name %q in routes[%d] and routes[%d]", route.Name, prev, i)
		}
		routeNames[route.Name] = i
		if err := validateBackendAddress(route.Backend); err != nil {
			return warnings, fmt.Errorf("routes[%d].backend: %w", i, err)
		}
		if len(route.SNI) == 0 {
			return warnings, fmt.Errorf("routes[%d].sni must not be empty", i)
		}
		for j, sni := range route.SNI {
			normalized := NormalizeSNI(sni)
			if !ValidSNIName(normalized) {
				return warnings, fmt.Errorf("routes[%d].sni[%d] is not a valid domain or wildcard: %q", i, j, sni)
			}
			if prev, ok := seen[normalized]; ok {
				return warnings, fmt.Errorf("duplicate sni %q in route %q and %q", normalized, prev, route.Name)
			}
			seen[normalized] = route.Name
			route.SNI[j] = normalized
		}
		for j, rule := range route.Whitelist {
			prefix, err := ParsePrefixRule(rule)
			if err != nil {
				return warnings, fmt.Errorf("routes[%d].whitelist[%d]: %w", i, j, err)
			}
			route.Whitelist[j] = prefix.String()
		}
		lowerName := strings.ToLower(route.Name)
		if len(route.Whitelist) == 0 && (strings.Contains(lowerName, "panel") || strings.Contains(lowerName, "subscription") || strings.Contains(lowerName, "sub")) {
			warnings = append(warnings, fmt.Sprintf("route %q looks sensitive but has no whitelist", route.Name))
		}
	}
	c.routeIndex = buildRouteIndex(c.Routes)
	return warnings, nil
}

func normalizeEnumDefault(value *string, fallback string, allowed map[string]struct{}) error {
	normalized := strings.ToLower(strings.TrimSpace(*value))
	if normalized == "" {
		*value = fallback
		return nil
	}
	if _, ok := allowed[normalized]; !ok {
		return fmt.Errorf("invalid value %q", *value)
	}
	*value = normalized
	return nil
}

func validateBackendAddress(addr string) error {
	if strings.TrimSpace(addr) == "" {
		return fmt.Errorf("address is empty")
	}
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return err
	}
	if host == "" {
		return fmt.Errorf("host is empty")
	}
	if port == "" {
		return fmt.Errorf("port is empty")
	}
	if _, err := net.ResolveTCPAddr("tcp", net.JoinHostPort(host, port)); err != nil {
		return err
	}
	return nil
}
