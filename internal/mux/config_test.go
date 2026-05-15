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
