package mux

import (
	"crypto/tls"
	"errors"
	"net"
	"testing"
)

func makeClientHello(t *testing.T, serverName string) []byte {
	t.Helper()
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()

	errCh := make(chan error, 1)
	go func() {
		cfg := &tls.Config{ServerName: serverName, InsecureSkipVerify: true}
		errCh <- tls.Client(client, cfg).Handshake()
	}()

	buf := make([]byte, 4096)
	n, err := server.Read(buf)
	if err != nil {
		t.Fatalf("read client hello: %v", err)
	}
	_ = server.Close()
	<-errCh
	return buf[:n]
}

func TestExtractSNI(t *testing.T) {
	hello := makeClientHello(t, "Panel.Example.COM")
	sni, err := ExtractSNI(hello)
	if err != nil {
		t.Fatalf("ExtractSNI returned error: %v", err)
	}
	if sni != "panel.example.com" {
		t.Fatalf("SNI = %q, want panel.example.com", sni)
	}
}

func TestExtractSNIWithoutSNI(t *testing.T) {
	hello := makeClientHello(t, "")
	_, err := ExtractSNI(hello)
	if !errors.Is(err, ErrNoSNI) {
		t.Fatalf("error = %v, want ErrNoSNI", err)
	}
}

func TestExtractSNINonTLS(t *testing.T) {
	_, err := ExtractSNI([]byte("GET / HTTP/1.1\r\n\r\n"))
	if !errors.Is(err, ErrInvalidClientHello) {
		t.Fatalf("error = %v, want ErrInvalidClientHello", err)
	}
}

func TestExtractSNIIncomplete(t *testing.T) {
	hello := makeClientHello(t, "site.example.com")
	_, err := ExtractSNI(hello[:10])
	if !errors.Is(err, ErrNeedMore) {
		t.Fatalf("error = %v, want ErrNeedMore", err)
	}
}
