package mux

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadConfigKeepsDefaultConnectionLimit(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "vpso-mux.yaml")
	data := []byte(`
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
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	if cfg.Limits.MaxConnections != 4096 {
		t.Fatalf("max_connections = %d, want 4096", cfg.Limits.MaxConnections)
	}
	if cfg.BackendRetry.Count != 0 {
		t.Fatalf("backend_retry.count = %d, want 0", cfg.BackendRetry.Count)
	}
	if cfg.BackendRetry.Delay != "200ms" {
		t.Fatalf("backend_retry.delay = %q, want 200ms", cfg.BackendRetry.Delay)
	}
	if cfg.Logging.MaxSizeBytes != 5*1024*1024 {
		t.Fatalf("logging.max_size_bytes = %d, want 5MiB", cfg.Logging.MaxSizeBytes)
	}
	if cfg.Logging.MaxBackups != 3 {
		t.Fatalf("logging.max_backups = %d, want 3", cfg.Logging.MaxBackups)
	}
}

func TestLoadConfigReadsStrictSNIGate(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "vpso-mux.yaml")
	data := []byte(`
listen:
  tcp:
    - "127.0.0.1:443"
default_backend: "127.0.0.1:1443"
reject_unknown_sni: true
routes:
  - name: "reality"
    sni:
      - "reality.example.com"
    backend: "127.0.0.1:1443"
`)
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	if !cfg.RejectUnknownSNI {
		t.Fatal("reject_unknown_sni = false, want true")
	}
}

func TestLoadConfigRejectsUnknownFields(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "vpso-mux.yaml")
	data := []byte(`
listen:
  tcp:
    - "127.0.0.1:443"
default_backend: "127.0.0.1:1443"
routes:
  - name: "panel"
    sni:
      - "panel.example.com"
    backend: "127.0.0.1:8443"
    whitelits:
      - "127.0.0.1/32"
`)
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	_, err := LoadConfig(path)
	if err == nil || !strings.Contains(err.Error(), "whitelits") {
		t.Fatalf("error = %v, want unknown field validation error", err)
	}
}

func TestValidateConfigRejectsNegativeConnectionLimit(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Listen.TCP = []string{"127.0.0.1:443"}
	cfg.DefaultBackend = "127.0.0.1:1443"
	cfg.Limits.MaxConnections = -1
	cfg.Routes = []Route{{
		Name:    "panel",
		SNI:     []string{"panel.example.com"},
		Backend: "127.0.0.1:8443",
	}}

	_, err := ValidateConfig(cfg)
	if err == nil || !strings.Contains(err.Error(), "limits.max_connections") {
		t.Fatalf("error = %v, want limits.max_connections validation error", err)
	}
}

func TestValidateConfigRejectsNegativeBackendRetryCount(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Listen.TCP = []string{"127.0.0.1:443"}
	cfg.DefaultBackend = "127.0.0.1:1443"
	cfg.BackendRetry.Count = -1
	cfg.Routes = []Route{{
		Name:    "panel",
		SNI:     []string{"panel.example.com"},
		Backend: "127.0.0.1:8443",
	}}

	_, err := ValidateConfig(cfg)
	if err == nil || !strings.Contains(err.Error(), "backend_retry.count") {
		t.Fatalf("error = %v, want backend_retry.count validation error", err)
	}
}

func TestValidateConfigRejectsDuplicateRouteName(t *testing.T) {
	cfg := validConfigForValidation()
	cfg.Routes = []Route{
		{Name: "panel", SNI: []string{"panel.example.com"}, Backend: "127.0.0.1:8443"},
		{Name: "panel", SNI: []string{"sub.example.com"}, Backend: "127.0.0.1:9443"},
	}

	_, err := ValidateConfig(cfg)
	if err == nil || !strings.Contains(err.Error(), "duplicate route name") {
		t.Fatalf("error = %v, want duplicate route name validation error", err)
	}
}

func TestValidateConfigLoggingEnumDefaults(t *testing.T) {
	cfg := validConfigForValidation()
	cfg.Logging.Level = ""
	cfg.Logging.Format = ""

	if _, err := ValidateConfig(cfg); err != nil {
		t.Fatalf("ValidateConfig: %v", err)
	}
	if cfg.Logging.Level != "info" {
		t.Fatalf("logging.level = %q, want info", cfg.Logging.Level)
	}
	if cfg.Logging.Format != "json" {
		t.Fatalf("logging.format = %q, want json", cfg.Logging.Format)
	}
}

func TestValidateConfigRejectsInvalidLoggingEnums(t *testing.T) {
	cfg := validConfigForValidation()
	cfg.Logging.Level = "trace"
	if _, err := ValidateConfig(cfg); err == nil || !strings.Contains(err.Error(), "logging.level") {
		t.Fatalf("error = %v, want logging.level validation error", err)
	}

	cfg = validConfigForValidation()
	cfg.Logging.Format = "yaml"
	if _, err := ValidateConfig(cfg); err == nil || !strings.Contains(err.Error(), "logging.format") {
		t.Fatalf("error = %v, want logging.format validation error", err)
	}
}

func validConfigForValidation() *Config {
	cfg := DefaultConfig()
	cfg.Listen.TCP = []string{"127.0.0.1:443"}
	cfg.DefaultBackend = "127.0.0.1:1443"
	cfg.Routes = []Route{{
		Name:    "panel",
		SNI:     []string{"panel.example.com"},
		Backend: "127.0.0.1:8443",
	}}
	return cfg
}
