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
