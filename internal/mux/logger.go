package mux

import (
	"encoding/json"
	"log"
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

type Logger struct{}

func NewLogger() *Logger {
	return &Logger{}
}

func (l *Logger) Emit(level string, ev LogEvent) {
	ev.Time = time.Now().Format(time.RFC3339Nano)
	ev.Level = level
	data, err := json.Marshal(ev)
	if err != nil {
		log.Printf(`{"level":"error","message":"failed to encode log event","error":%q}`, err.Error())
		return
	}
	log.Print(string(data))
}
