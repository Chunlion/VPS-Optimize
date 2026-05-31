package mux

import (
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type LogEvent struct {
	Time         string `json:"time"`
	Level        string `json:"level"`
	ClientIP     string `json:"client_ip,omitempty"`
	SNI          string `json:"sni,omitempty"`
	Backend      string `json:"backend,omitempty"`
	RouteName    string `json:"route_name,omitempty"`
	Allowed      *bool  `json:"allowed,omitempty"`
	Blocked      bool   `json:"blocked,omitempty"`
	TransferMode string `json:"transfer_mode,omitempty"`
	Error        string `json:"error,omitempty"`
	Message      string `json:"message,omitempty"`
}

type LoggerOptions struct {
	File         string
	MaxSizeBytes int64
	MaxBackups   int
}

type Logger struct {
	mu           sync.Mutex
	filePath     string
	maxSizeBytes int64
	maxBackups   int
	file         *os.File
}

func NewLogger(options ...LoggerOptions) *Logger {
	logger := &Logger{
		maxSizeBytes: 5 * 1024 * 1024,
		maxBackups:   3,
	}
	if len(options) > 0 {
		opt := options[0]
		logger.filePath = opt.File
		if opt.MaxSizeBytes > 0 {
			logger.maxSizeBytes = opt.MaxSizeBytes
		}
		if opt.MaxBackups >= 0 {
			logger.maxBackups = opt.MaxBackups
		}
	}
	return logger
}

func (l *Logger) Emit(level string, ev LogEvent) {
	ev.Time = time.Now().Format(time.RFC3339Nano)
	ev.Level = level
	data, err := json.Marshal(ev)
	if err != nil {
		log.Printf(`{"level":"error","message":"failed to encode log event","error":%q}`, err.Error())
		return
	}
	line := string(data)
	log.Print(line)
	l.writeFile(line + "\n")
}

func (l *Logger) Close() error {
	if l == nil {
		return nil
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.file == nil {
		return nil
	}
	err := l.file.Close()
	l.file = nil
	return err
}

func (l *Logger) writeFile(line string) {
	if l == nil || l.filePath == "" {
		return
	}
	l.mu.Lock()
	defer l.mu.Unlock()

	if err := l.rotateIfNeeded(int64(len(line))); err != nil {
		log.Printf(`{"level":"error","message":"failed to rotate log file","error":%q}`, err.Error())
		return
	}
	if l.file == nil {
		if err := os.MkdirAll(filepath.Dir(l.filePath), 0755); err != nil {
			log.Printf(`{"level":"error","message":"failed to create log directory","error":%q}`, err.Error())
			return
		}
		file, err := os.OpenFile(l.filePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0640)
		if err != nil {
			log.Printf(`{"level":"error","message":"failed to open log file","error":%q}`, err.Error())
			return
		}
		l.file = file
	}
	if _, err := l.file.WriteString(line); err != nil {
		log.Printf(`{"level":"error","message":"failed to write log file","error":%q}`, err.Error())
	}
}

func (l *Logger) rotateIfNeeded(incomingBytes int64) error {
	if l.filePath == "" || l.maxSizeBytes <= 0 {
		return nil
	}
	info, err := os.Stat(l.filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if info.Size()+incomingBytes < l.maxSizeBytes {
		return nil
	}
	if l.file != nil {
		if err := l.file.Close(); err != nil {
			return err
		}
		l.file = nil
	}
	if l.maxBackups <= 0 {
		return os.Truncate(l.filePath, 0)
	}
	if err := os.Remove(l.filePath + "." + itoa(l.maxBackups)); err != nil && !os.IsNotExist(err) {
		return err
	}
	for i := l.maxBackups - 1; i >= 1; i-- {
		oldPath := l.filePath + "." + itoa(i)
		newPath := l.filePath + "." + itoa(i+1)
		if err := os.Rename(oldPath, newPath); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	if err := os.Rename(l.filePath, l.filePath+".1"); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func itoa(value int) string {
	if value == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for value > 0 {
		i--
		buf[i] = byte('0' + value%10)
		value /= 10
	}
	return string(buf[i:])
}
