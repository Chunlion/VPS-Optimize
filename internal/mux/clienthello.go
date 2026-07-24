package mux

import (
	"errors"
	"strings"
)

var (
	ErrNeedMore           = errors.New("need more data")
	ErrInvalidClientHello = errors.New("invalid tls client hello")
	ErrNoSNI              = errors.New("client hello has no sni")
)

const (
	tlsRecordHandshake  = 0x16
	tlsHandshakeClient  = 0x01
	extensionServerName = 0x0000
	nameTypeHostName    = 0x00
)

func ExtractSNI(data []byte) (string, error) {
	hello, err := collectClientHello(data)
	if err != nil {
		return "", err
	}
	pos := 0
	helloEnd := len(hello)

	if pos+2+32 > helloEnd {
		return "", ErrInvalidClientHello
	}
	pos += 2 + 32 // legacy_version + random

	if pos+1 > helloEnd {
		return "", ErrInvalidClientHello
	}
	sessionLen := int(hello[pos])
	pos++
	if pos+sessionLen > helloEnd {
		return "", ErrInvalidClientHello
	}
	pos += sessionLen

	if pos+2 > helloEnd {
		return "", ErrInvalidClientHello
	}
	cipherLen := int(hello[pos])<<8 | int(hello[pos+1])
	pos += 2
	if cipherLen == 0 || cipherLen%2 != 0 || pos+cipherLen > helloEnd {
		return "", ErrInvalidClientHello
	}
	pos += cipherLen

	if pos+1 > helloEnd {
		return "", ErrInvalidClientHello
	}
	compressionLen := int(hello[pos])
	pos++
	if compressionLen == 0 || pos+compressionLen > helloEnd {
		return "", ErrInvalidClientHello
	}
	pos += compressionLen

	if pos == helloEnd {
		return "", ErrNoSNI
	}
	if pos+2 > helloEnd {
		return "", ErrInvalidClientHello
	}
	extensionsLen := int(hello[pos])<<8 | int(hello[pos+1])
	pos += 2
	if pos+extensionsLen != helloEnd {
		return "", ErrInvalidClientHello
	}
	extensionsEnd := pos + extensionsLen

	for pos < extensionsEnd {
		if pos+4 > extensionsEnd {
			return "", ErrInvalidClientHello
		}
		extType := uint16(hello[pos])<<8 | uint16(hello[pos+1])
		extLen := int(hello[pos+2])<<8 | int(hello[pos+3])
		pos += 4
		if pos+extLen > extensionsEnd {
			return "", ErrInvalidClientHello
		}
		if extType == extensionServerName {
			return parseServerNameExtension(hello[pos : pos+extLen])
		}
		pos += extLen
	}

	return "", ErrNoSNI
}

func collectClientHello(data []byte) ([]byte, error) {
	var handshake []byte
	helloLen := -1

	for pos := 0; ; {
		if len(data)-pos < 5 {
			return nil, ErrNeedMore
		}
		if data[pos] != tlsRecordHandshake {
			return nil, ErrInvalidClientHello
		}
		recordLen := int(data[pos+3])<<8 | int(data[pos+4])
		if recordLen <= 0 {
			return nil, ErrInvalidClientHello
		}
		recordEnd := pos + 5 + recordLen
		if recordEnd > len(data) {
			return nil, ErrNeedMore
		}
		handshake = append(handshake, data[pos+5:recordEnd]...)
		if len(handshake) > 0 && handshake[0] != tlsHandshakeClient {
			return nil, ErrInvalidClientHello
		}
		if len(handshake) >= 4 {
			helloLen = int(handshake[1])<<16 | int(handshake[2])<<8 | int(handshake[3])
			if helloLen <= 0 {
				return nil, ErrInvalidClientHello
			}
			if len(handshake) >= 4+helloLen {
				return handshake[4 : 4+helloLen], nil
			}
		}
		pos = recordEnd
		if pos == len(data) {
			return nil, ErrNeedMore
		}
	}
}

func parseServerNameExtension(data []byte) (string, error) {
	if len(data) < 2 {
		return "", ErrInvalidClientHello
	}
	listLen := int(data[0])<<8 | int(data[1])
	if listLen == 0 {
		return "", ErrNoSNI
	}
	if len(data) != 2+listLen {
		return "", ErrInvalidClientHello
	}

	pos := 2
	end := 2 + listLen
	for pos < end {
		if pos+3 > end {
			return "", ErrInvalidClientHello
		}
		nameType := data[pos]
		nameLen := int(data[pos+1])<<8 | int(data[pos+2])
		pos += 3
		if pos+nameLen > end {
			return "", ErrInvalidClientHello
		}
		if nameType == nameTypeHostName {
			name := strings.TrimSuffix(strings.ToLower(string(data[pos:pos+nameLen])), ".")
			if !ValidSNIName(name) {
				return "", ErrInvalidClientHello
			}
			return name, nil
		}
		pos += nameLen
	}

	return "", ErrNoSNI
}
