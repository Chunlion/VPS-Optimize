package mux

import (
	"net/netip"
	"strings"
	"testing"
)

func TestRouteExactMatch(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Listen.TCP = []string{"127.0.0.1:443"}
	cfg.DefaultBackend = "127.0.0.1:1443"
	cfg.Routes = []Route{{Name: "panel", SNI: []string{"panel.example.com"}, Backend: "127.0.0.1:8443"}}
	if _, err := ValidateConfig(cfg); err != nil {
		t.Fatalf("ValidateConfig: %v", err)
	}
	match := MatchRoute(cfg, "panel.example.com", netip.MustParseAddr("203.0.113.8"))
	if match.Backend != "127.0.0.1:8443" || !match.Allowed {
		t.Fatalf("unexpected match: %+v", match)
	}
}

func TestRouteWildcardMatch(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Listen.TCP = []string{"127.0.0.1:443"}
	cfg.DefaultBackend = "127.0.0.1:1443"
	cfg.Routes = []Route{{Name: "wild", SNI: []string{"*.example.com"}, Backend: "127.0.0.1:8443"}}
	if _, err := ValidateConfig(cfg); err != nil {
		t.Fatalf("ValidateConfig: %v", err)
	}
	match := MatchRoute(cfg, "www.example.com", netip.MustParseAddr("203.0.113.8"))
	if match.RouteName != "wild" || !match.Allowed {
		t.Fatalf("unexpected match: %+v", match)
	}
	if MatchRoute(cfg, "deep.www.example.com", netip.MustParseAddr("203.0.113.8")).RouteName != "default" {
		t.Fatalf("wildcard should only match one label")
	}
}

func TestRouteIndexExactMatchWinsOverWildcard(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Listen.TCP = []string{"127.0.0.1:443"}
	cfg.DefaultBackend = "127.0.0.1:1443"
	cfg.Routes = []Route{
		{Name: "wild", SNI: []string{"*.example.com"}, Backend: "127.0.0.1:8443"},
		{Name: "exact", SNI: []string{"panel.example.com"}, Backend: "127.0.0.1:9443"},
	}
	if _, err := ValidateConfig(cfg); err != nil {
		t.Fatalf("ValidateConfig: %v", err)
	}
	if cfg.routeIndex == nil {
		t.Fatalf("ValidateConfig did not build route index")
	}
	match := MatchRoute(cfg, "panel.example.com", netip.MustParseAddr("203.0.113.8"))
	if match.RouteName != "exact" || match.Backend != "127.0.0.1:9443" {
		t.Fatalf("unexpected match: %+v", match)
	}
}

func TestWhitelistIPv4IPv6AndCIDR(t *testing.T) {
	rules := []string{"1.2.3.4", "2001:db8::/32", "10.0.0.0/8"}
	cases := []string{"1.2.3.4", "2001:db8::1", "10.20.30.40"}
	for _, item := range cases {
		if !IPAllowed(netip.MustParseAddr(item), rules) {
			t.Fatalf("%s should be allowed", item)
		}
	}
	if IPAllowed(netip.MustParseAddr("198.51.100.1"), rules) {
		t.Fatalf("198.51.100.1 should be blocked")
	}
}

func TestRouteWhitelistBlocksClient(t *testing.T) {
	cfg := DefaultConfig()
	cfg.DefaultBackend = "127.0.0.1:1443"
	cfg.Routes = []Route{{
		Name:      "panel",
		SNI:       []string{"panel.example.com"},
		Backend:   "127.0.0.1:8443",
		Whitelist: []string{"1.2.3.4/32"},
	}}
	match := MatchRoute(cfg, "panel.example.com", netip.MustParseAddr("198.51.100.9"))
	if match.Allowed || !match.Blocked || match.Backend != "" {
		t.Fatalf("unexpected whitelist decision: %+v", match)
	}
}

func TestDuplicateSNIConflict(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Listen.TCP = []string{"127.0.0.1:443"}
	cfg.DefaultBackend = "127.0.0.1:1443"
	cfg.Routes = []Route{
		{Name: "a", SNI: []string{"panel.example.com"}, Backend: "127.0.0.1:8443"},
		{Name: "b", SNI: []string{"panel.example.com"}, Backend: "127.0.0.1:1443"},
	}
	_, err := ValidateConfig(cfg)
	if err == nil || !strings.Contains(err.Error(), "duplicate sni") {
		t.Fatalf("error = %v, want duplicate sni", err)
	}
}

func TestDefaultBackend(t *testing.T) {
	cfg := DefaultConfig()
	cfg.DefaultBackend = "127.0.0.1:1443"
	match := MatchRoute(cfg, "random.example.com", netip.MustParseAddr("203.0.113.8"))
	if match.RouteName != "default" || match.Backend != "127.0.0.1:1443" || !match.Allowed {
		t.Fatalf("unexpected default match: %+v", match)
	}
}
