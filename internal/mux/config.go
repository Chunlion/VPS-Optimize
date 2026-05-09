package mux

import (
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
	Splice struct {
		Enabled        bool `yaml:"enabled"`
		PipeSize       int  `yaml:"pipe_size"`
		FallbackToCopy bool `yaml:"fallback_to_copy"`
	} `yaml:"splice"`
	DefaultBackend string  `yaml:"default_backend"`
	Routes         []Route `yaml:"routes"`
	Logging        struct {
		Level  string `yaml:"level"`
		Format string `yaml:"format"`
	} `yaml:"logging"`
}

type Durations struct {
	Peek     time.Duration
	Dial     time.Duration
	Idle     time.Duration
	Shutdown time.Duration
}

func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	cfg := DefaultConfig()
	if err := yaml.Unmarshal(data, cfg); err != nil {
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
	cfg.Splice.Enabled = true
	cfg.Splice.PipeSize = 1048576
	cfg.Splice.FallbackToCopy = true
	cfg.Logging.Level = "info"
	cfg.Logging.Format = "json"
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

	seen := map[string]string{}
	for i := range c.Routes {
		route := &c.Routes[i]
		route.Name = strings.TrimSpace(route.Name)
		if route.Name == "" {
			return warnings, fmt.Errorf("routes[%d].name must not be empty", i)
		}
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
	return warnings, nil
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
