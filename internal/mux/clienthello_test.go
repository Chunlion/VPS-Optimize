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

func TestServerNameExtensionRejectsAmbiguousNames(t *testing.T) {
	for _, name := range []string{"*.example.com", " panel.example.com", "panel.example.com "} {
		entry := append([]byte{0, 0, byte(len(name))}, name...)
		data := append([]byte{0, byte(len(entry))}, entry...)
		if _, err := parseServerNameExtension(data); !errors.Is(err, ErrInvalidClientHello) {
			t.Fatalf("name %q: got %v, want invalid ClientHello", name, err)
		}
	}
	name := "panel.example.com"
	entry := append([]byte{0, 0, byte(len(name))}, name...)
	for _, suffix := range [][]byte{entry, {0}} {
		data := append([]byte{0, byte(len(entry) + len(suffix))}, entry...)
		data = append(data, suffix...)
		if _, err := parseServerNameExtension(data); !errors.Is(err, ErrInvalidClientHello) {
			t.Fatalf("duplicate or truncated name: got %v", err)
		}
	}
}

func TestExtractSNIValidatesExtensionsAfterServerName(t *testing.T) {
	hello := makeClientHello(t, "panel.example.com")
	pos := 9 + 34
	pos += 1 + int(hello[pos])
	pos += 2 + int(hello[pos])<<8 + int(hello[pos+1])
	pos += 1 + int(hello[pos])
	for _, suffix := range [][]byte{{0}, {0, 0, 0, 0}} {
		data := append(append([]byte(nil), hello...), suffix...)
		for _, offset := range []int{3, 7, pos} {
			length := int(hello[offset])<<8 | int(hello[offset+1])
			length += len(suffix)
			data[offset], data[offset+1] = byte(length>>8), byte(length)
		}
		if _, err := ExtractSNI(data); !errors.Is(err, ErrInvalidClientHello) {
			t.Fatalf("trailing malformed or duplicate SNI extension: got %v", err)
		}
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

func TestExtractSNIFromFragmentedTLSRecords(t *testing.T) {
	hello := makeClientHello(t, "fragmented.example.com")
	recordLen := int(hello[3])<<8 | int(hello[4])
	if len(hello) < 5+recordLen || recordLen < 16 {
		t.Fatalf("unexpected ClientHello record length: %d", recordLen)
	}
	payload := hello[5 : 5+recordLen]
	split := 11
	fragmented := appendTLSRecord(nil, hello[1:3], payload[:split])
	fragmented = appendTLSRecord(fragmented, hello[1:3], payload[split:])

	sni, err := ExtractSNI(fragmented)
	if err != nil {
		t.Fatalf("ExtractSNI returned error: %v", err)
	}
	if sni != "fragmented.example.com" {
		t.Fatalf("SNI = %q, want fragmented.example.com", sni)
	}
}

func TestExtractSNIFromIncompleteFragmentedTLSRecords(t *testing.T) {
	hello := makeClientHello(t, "fragmented.example.com")
	recordLen := int(hello[3])<<8 | int(hello[4])
	payload := hello[5 : 5+recordLen]
	fragmented := appendTLSRecord(nil, hello[1:3], payload[:11])

	_, err := ExtractSNI(fragmented)
	if !errors.Is(err, ErrNeedMore) {
		t.Fatalf("error = %v, want ErrNeedMore", err)
	}
}

func TestCollectClientHelloSingleRecordDoesNotAllocate(t *testing.T) {
	hello := makeClientHello(t, "panel.example.com")
	allocs := testing.AllocsPerRun(100, func() {
		if _, err := collectClientHello(hello); err != nil {
			t.Fatal(err)
		}
	})
	if allocs != 0 {
		t.Fatalf("allocations = %v, want 0", allocs)
	}
}

func TestExtractSNIWithFragmentedHandshakeHeader(t *testing.T) {
	hello := makeClientHello(t, "panel.example.com")
	for split := 1; split <= 4; split++ {
		fragmented := appendTLSRecord(nil, hello[1:3], hello[5:5+split])
		fragmented = appendTLSRecord(fragmented, hello[1:3], hello[5+split:])
		sni, err := ExtractSNI(fragmented)
		if err != nil || sni != "panel.example.com" {
			t.Fatalf("split %d: %q, %v", split, sni, err)
		}
	}
}

func appendTLSRecord(dst []byte, version []byte, payload []byte) []byte {
	dst = append(dst, tlsRecordHandshake, version[0], version[1], byte(len(payload)>>8), byte(len(payload)))
	return append(dst, payload...)
}
