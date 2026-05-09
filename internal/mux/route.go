package mux

import (
	"net/netip"
	"regexp"
	"strings"
)

type Route struct {
	Name       string   `yaml:"name"`
	SNI        []string `yaml:"sni"`
	Backend    string   `yaml:"backend"`
	Whitelist  []string `yaml:"whitelist,omitempty"`
	Blackhole  string   `yaml:"blackhole_backend,omitempty"`
	RejectMode string   `yaml:"reject,omitempty"`
}

type Match struct {
	Backend   string
	RouteName string
	Allowed   bool
	Blocked   bool
}

var domainLabelPattern = regexp.MustCompile(`^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$`)

func NormalizeSNI(sni string) string {
	sni = strings.TrimSpace(strings.ToLower(sni))
	sni = strings.TrimSuffix(sni, ".")
	return sni
}

func ValidSNIName(sni string) bool {
	sni = NormalizeSNI(sni)
	if sni == "" || len(sni) > 253 {
		return false
	}
	if strings.HasPrefix(sni, "*.") {
		return validDomain(sni[2:])
	}
	return validDomain(sni)
}

func validDomain(domain string) bool {
	if domain == "" || strings.Contains(domain, "..") {
		return false
	}
	labels := strings.Split(domain, ".")
	if len(labels) < 2 {
		return false
	}
	for _, label := range labels {
		if !domainLabelPattern.MatchString(label) {
			return false
		}
	}
	return true
}

func MatchRoute(c *Config, sni string, clientIP netip.Addr) Match {
	sni = NormalizeSNI(sni)
	if c == nil {
		return Match{Allowed: false, Blocked: true}
	}

	if sni != "" {
		for i := range c.Routes {
			route := &c.Routes[i]
			if routeMatches(route, sni, false) {
				return matchRouteAllowed(route, clientIP)
			}
		}
		for i := range c.Routes {
			route := &c.Routes[i]
			if routeMatches(route, sni, true) {
				return matchRouteAllowed(route, clientIP)
			}
		}
	}

	return Match{
		Backend:   c.DefaultBackend,
		RouteName: "default",
		Allowed:   true,
	}
}

func routeMatches(route *Route, sni string, wildcardOnly bool) bool {
	for _, item := range route.SNI {
		item = NormalizeSNI(item)
		if strings.HasPrefix(item, "*.") {
			if wildcardOnly && wildcardMatch(item, sni) {
				return true
			}
			continue
		}
		if !wildcardOnly && item == sni {
			return true
		}
	}
	return false
}

func wildcardMatch(pattern, sni string) bool {
	suffix := strings.TrimPrefix(pattern, "*")
	if suffix == "" || !strings.HasSuffix(sni, suffix) {
		return false
	}
	prefix := strings.TrimSuffix(sni, suffix)
	return prefix != "" && !strings.Contains(prefix, ".")
}

func matchRouteAllowed(route *Route, clientIP netip.Addr) Match {
	match := Match{
		Backend:   route.Backend,
		RouteName: route.Name,
		Allowed:   true,
	}
	if len(route.Whitelist) == 0 {
		return match
	}
	if !clientIP.IsValid() {
		match.Allowed = false
		match.Blocked = true
		return match
	}
	if IPAllowed(clientIP, route.Whitelist) {
		return match
	}
	match.Allowed = false
	match.Blocked = true
	if route.Blackhole != "" {
		match.Backend = route.Blackhole
	} else {
		match.Backend = ""
	}
	return match
}
