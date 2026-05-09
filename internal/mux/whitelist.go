package mux

import (
	"fmt"
	"net/netip"
	"strings"
)

func ParsePrefixRule(rule string) (netip.Prefix, error) {
	rule = strings.TrimSpace(strings.ToLower(rule))
	if rule == "" {
		return netip.Prefix{}, fmt.Errorf("empty ip/cidr rule")
	}
	if strings.Contains(rule, "/") {
		prefix, err := netip.ParsePrefix(rule)
		if err != nil {
			return netip.Prefix{}, err
		}
		return prefix.Masked(), nil
	}
	addr, err := netip.ParseAddr(rule)
	if err != nil {
		return netip.Prefix{}, err
	}
	if addr.Is4() {
		return netip.PrefixFrom(addr, 32), nil
	}
	return netip.PrefixFrom(addr, 128), nil
}

func IPAllowed(addr netip.Addr, rules []string) bool {
	if !addr.IsValid() {
		return false
	}
	for _, rule := range rules {
		prefix, err := ParsePrefixRule(rule)
		if err != nil {
			continue
		}
		if prefix.Contains(addr) {
			return true
		}
	}
	return false
}
