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
	tlsRecordHandshake = 0x16
	tlsHandshakeClient = 0x01
	extensionServerName = 0x0000
	nameTypeHostName    = 0x00
)

func ExtractSNI(data []byte) (string, error) {
	if len(data) < 5 {
		return "", ErrNeedMore
	}
	if data[0] != tlsRecordHandshake {
		return "", ErrInvalidClientHello
	}

	recordLen := int(data[3])<<8 | int(data[4])
	if recordLen <= 0 {
		return "", ErrInvalidClientHello
	}
	if len(data) < 5+recordLen {
		return "", ErrNeedMore
	}

	pos := 5
	recordEnd := 5 + recordLen
	if pos+4 > recordEnd {
		return "", ErrNeedMore
	}
	if data[pos] != tlsHandshakeClient {
		return "", ErrInvalidClientHello
	}
	helloLen := int(data[pos+1])<<16 | int(data[pos+2])<<8 | int(data[pos+3])
	pos += 4
	if helloLen <= 0 {
		return "", ErrInvalidClientHello
	}
	if pos+helloLen > recordEnd {
		return "", ErrNeedMore
	}
	helloEnd := pos + helloLen

	if pos+2+32 > helloEnd {
		return "", ErrNeedMore
	}
	pos += 2 + 32 // legacy_version + random

	if pos+1 > helloEnd {
		return "", ErrNeedMore
	}
	sessionLen := int(data[pos])
	pos++
	if pos+sessionLen > helloEnd {
		return "", ErrNeedMore
	}
	pos += sessionLen

	if pos+2 > helloEnd {
		return "", ErrNeedMore
	}
	cipherLen := int(data[pos])<<8 | int(data[pos+1])
	pos += 2
	if cipherLen == 0 || cipherLen%2 != 0 || pos+cipherLen > helloEnd {
		return "", ErrInvalidClientHello
	}
	pos += cipherLen

	if pos+1 > helloEnd {
		return "", ErrNeedMore
	}
	compressionLen := int(data[pos])
	pos++
	if compressionLen == 0 || pos+compressionLen > helloEnd {
		return "", ErrInvalidClientHello
	}
	pos += compressionLen

	if pos == helloEnd {
		return "", ErrNoSNI
	}
	if pos+2 > helloEnd {
		return "", ErrNeedMore
	}
	extensionsLen := int(data[pos])<<8 | int(data[pos+1])
	pos += 2
	if pos+extensionsLen > helloEnd {
		return "", ErrNeedMore
	}
	extensionsEnd := pos + extensionsLen

	for pos < extensionsEnd {
		if pos+4 > extensionsEnd {
			return "", ErrNeedMore
		}
		extType := uint16(data[pos])<<8 | uint16(data[pos+1])
		extLen := int(data[pos+2])<<8 | int(data[pos+3])
		pos += 4
		if pos+extLen > extensionsEnd {
			return "", ErrNeedMore
		}
		if extType == extensionServerName {
			return parseServerNameExtension(data[pos : pos+extLen])
		}
		pos += extLen
	}

	return "", ErrNoSNI
}

func parseServerNameExtension(data []byte) (string, error) {
	if len(data) < 2 {
		return "", ErrNeedMore
	}
	listLen := int(data[0])<<8 | int(data[1])
	if listLen == 0 {
		return "", ErrNoSNI
	}
	if len(data) < 2+listLen {
		return "", ErrNeedMore
	}

	pos := 2
	end := 2 + listLen
	for pos < end {
		if pos+3 > end {
			return "", ErrNeedMore
		}
		nameType := data[pos]
		nameLen := int(data[pos+1])<<8 | int(data[pos+2])
		pos += 3
		if pos+nameLen > end {
			return "", ErrNeedMore
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
