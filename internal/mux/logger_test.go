package mux

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoggerRotatesFile(t *testing.T) {
	logPath := filepath.Join(t.TempDir(), "vpso-mux.log")
	logger := NewLogger(LoggerOptions{
		File:         logPath,
		MaxSizeBytes: 120,
		MaxBackups:   2,
	})
	defer logger.Close()

	for i := 0; i < 6; i++ {
		logger.Emit("info", LogEvent{Message: strings.Repeat("x", 80)})
	}

	if _, err := os.Stat(logPath + ".1"); err != nil {
		t.Fatalf("rotated log %s.1 missing: %v", logPath, err)
	}
	if _, err := os.Stat(logPath + ".3"); !os.IsNotExist(err) {
		t.Fatalf("unexpected backup beyond retention: %v", err)
	}
}

func TestLoggerFiltersBelowConfiguredLevel(t *testing.T) {
	logPath := filepath.Join(t.TempDir(), "vpso-mux.log")
	logger := NewLogger(LoggerOptions{
		Level:  "warn",
		Format: "json",
		File:   logPath,
	})
	logger.Emit("info", LogEvent{Message: "hidden"})
	logger.Emit("error", LogEvent{Message: "visible"})
	if err := logger.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	text := string(data)
	if strings.Contains(text, "hidden") || !strings.Contains(text, "visible") {
		t.Fatalf("filtered log output = %q", text)
	}
}

func TestLoggerWritesTextFormat(t *testing.T) {
	logPath := filepath.Join(t.TempDir(), "vpso-mux.log")
	logger := NewLogger(LoggerOptions{
		Level:  "debug",
		Format: "text",
		File:   logPath,
	})
	logger.Emit("info", LogEvent{SNI: "panel.example.com", Message: "connected"})
	if err := logger.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	text := string(data)
	if strings.HasPrefix(strings.TrimSpace(text), "{") {
		t.Fatalf("text log must not be JSON: %q", text)
	}
	if !strings.Contains(text, `level="info"`) || !strings.Contains(text, `sni="panel.example.com"`) {
		t.Fatalf("text log output = %q", text)
	}
}
