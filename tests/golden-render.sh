#!/usr/bin/env bash
set -euo pipefail
trap 'echo "golden-render failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail_golden_assertion() {
    echo "$1" >&2
    return 1
}

assert_contains() {
    local file="$1"
    local needle="$2"
    grep -Fq "$needle" "$file" || fail_golden_assertion "Missing expected text in $file: $needle"
}

assert_not_contains() {
    local file="$1"
    local needle="$2"
    ! grep -Fq "$needle" "$file" || fail_golden_assertion "Unexpected text in $file: $needle"
}

assert_grep_count() {
    local file="$1"
    local pattern="$2"
    local expected="$3"
    local actual
    actual=$(grep -Ec "$pattern" "$file" || true)
    [[ "$actual" == "$expected" ]] || fail_golden_assertion "Expected $expected matches for $pattern in $file, got $actual"
}

route_block() {
    local file="$1"
    local route_name="$2"
    awk -v marker="  - name: '${route_name}'" '
        $0 == marker {in_route=1; print; next}
        in_route && /^  - name: / {exit}
        in_route {print}
    ' "$file"
}

assert_route() {
    local file="$1"
    local route_name="$2"
    local sni="$3"
    local backend="$4"
    local block range
    block=$(route_block "$file" "$route_name")
    [[ -n "$block" ]] || fail_golden_assertion "Missing route: $route_name"
    grep -Fq "      - '${sni}'" <<<"$block" || fail_golden_assertion "Route $route_name must match SNI $sni."
    grep -Fq "    backend: '${backend}'" <<<"$block" || fail_golden_assertion "Route $route_name must use backend $backend."
    if [[ "$#" -gt 4 ]]; then
        grep -Fq "    whitelist:" <<<"$block" || fail_golden_assertion "Route $route_name must carry Web whitelist rules."
        for range in "${@:5}"; do
            grep -Fq "      - '${range}'" <<<"$block" || fail_golden_assertion "Route $route_name must carry Web whitelist entry $range."
        done
    else
        ! grep -Fq "    whitelist:" <<<"$block" || fail_golden_assertion "Route $route_name must not receive Web whitelist rules."
    fi
}

assert_route_before() {
    local file="$1"
    local first_route="$2"
    local second_route="$3"
    local first_line second_line
    first_line=$(grep -nF "  - name: '${first_route}'" "$file" | head -n 1 | cut -d: -f1)
    second_line=$(grep -nF "  - name: '${second_route}'" "$file" | head -n 1 | cut -d: -f1)
    [[ -n "$first_line" ]] || fail_golden_assertion "Missing route: $first_route"
    [[ -n "$second_line" ]] || fail_golden_assertion "Missing route: $second_route"
    (( first_line < second_line )) || fail_golden_assertion "Route $first_route must render before broader route $second_route."
}

assert_nginx_single_entry_web_render() {
    local file="$1"
    local needle
    assert_grep_count "$file" '^server \{' 2
    for needle in \
        "listen 127.0.0.1:8443 ssl http2;" \
        "server_name panel.example.com;" \
        "ssl_certificate /etc/caddy/certs/panel.example.com.crt;" \
        "location ^~ /sub/ {" \
        "location ^~ /clash/ {" \
        "proxy_set_header X-Forwarded-Port 443;" \
        "proxy_pass http://127.0.0.1:2096;" \
        "proxy_pass http://127.0.0.1:40000;" \
        "server_name site.example.com;" \
        "ssl_certificate /etc/caddy/certs/site.example.com.crt;" \
        "proxy_pass http://127.0.0.1:3000;"; do
        assert_contains "$file" "$needle"
    done
    for needle in "listen 443 ssl" "listen 0.0.0.0:443" "listen [::]:443" "server_name tcp.example.com;" "server_name node.example.com;"; do
        assert_not_contains "$file" "$needle"
    done
}

assert_nginx_reverse_proxy_render() {
    local file="$1"
    local needle
    for needle in \
        "server_name proxy.example.com;" \
        "# vps-optimize-ip-whitelist-start" \
        "allow 198.51.100.10;" \
        "allow 2001:db8::/32;" \
        "deny all;" \
        "# vps-optimize-ip-whitelist-end" \
        "proxy_pass http://127.0.0.1:40000;"; do
        assert_contains "$file" "$needle"
    done
}

assert_vpso_mux_render() {
    local file="$1"
    assert_contains "$file" "    - '0.0.0.0:443'"
    assert_contains "$file" "default_backend: '127.0.0.1:1443'"
    assert_route "$file" "panel" "panel.example.com" "127.0.0.1:8443" "198.51.100.10" "2001:db8::/32"
    assert_route "$file" "site_site_example_com" "site.example.com" "127.0.0.1:8443" "203.0.113.5"
    assert_route "$file" "tcp_tcp_example_com" "tcp.example.com" "127.0.0.1:2443"
    assert_route "$file" "tcp_api_example_com" "api.example.com" "127.0.0.1:2444"
    assert_route "$file" "tcp__example_com" "*.example.com" "127.0.0.1:2445"
    assert_route_before "$file" "panel" "tcp__example_com"
    assert_route_before "$file" "tcp_api_example_com" "tcp__example_com"
    assert_route "$file" "xray_node_example_com" "node.example.com" "127.0.0.1:3443"
    assert_route "$file" "reality" "reality.example.com" "127.0.0.1:1443"
}

tmp_dir=$(mktemp -d /tmp/vps-golden-render.XXXXXX)
cleanup_golden_tmp() {
    [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]] || return 0
    rm -f "$tmp_dir/nginx-single-entry-web.conf"
    rm -f "$tmp_dir/nginx-reverse-proxy.conf"
    rm -f "$tmp_dir/vpso-mux.yaml"
    rm -f "$tmp_dir/nginx-strict-sni.conf"
    rm -f "$tmp_dir/disable-ipv6"
    rmdir "$tmp_dir" 2>/dev/null || true
}
trap cleanup_golden_tmp EXIT

source src/input.sh
source src/validate.sh
source src/sni_stack_config.sh
source src/sni_stack_whitelist_state.sh
source src/vpso_mux_state.sh
source src/vpso_mux_config.sh
source src/reality_guard.sh
source src/sni_stack_install.sh
source src/caddy_proxy.sh

NGINX_LISTEN_ADDR=0.0.0.0
NGINX_LISTEN_PORT=443
CADDY_LISTEN_ADDR=127.0.0.1
CADDY_LISTEN_PORT=8443
PANEL_DOMAIN=panel.example.com
PANEL_LISTEN_ADDR=127.0.0.1
PANEL_LISTEN_PORT=40000
SUB_LISTEN_ADDR=127.0.0.1
SUB_LISTEN_PORT=2096
SUB_URI_PATH=/sub/
CLASH_URI_PATH=/clash/
SITE_DOMAINS=(site.example.com)
SITE_BACKEND_ADDRS=(127.0.0.1)
SITE_BACKEND_PORTS=(3000)
XRAY_LISTEN_ADDR=127.0.0.1
XRAY_LISTEN_PORT=1443
REALITY_SNI=reality.example.com
TCP_ROUTE_SNIS=(tcp.example.com api.example.com "*.example.com")
TCP_ROUTE_ADDRS=(127.0.0.1 127.0.0.1 127.0.0.1)
TCP_ROUTE_PORTS=(2443 2444 2445)
XRAY_SNI_ROUTE_SNIS=(node.example.com)
XRAY_SNI_ROUTE_ADDRS=(127.0.0.1)
XRAY_SNI_ROUTE_PORTS=(3443)
SNI_IP_WHITELIST_DOMAINS=(panel.example.com site.example.com)
SNI_IP_WHITELIST_RANGES=("198.51.100.10 2001:db8::/32" "203.0.113.5")
WEB_PROXY_ENGINE=nginx
STRICT_SNI_GATE=false

VPSO_PROC_NET_IF_INET6="$tmp_dir/no-ipv6"
VPSO_PROC_SYS_DISABLE_IPV6="$tmp_dir/disable-ipv6"
printf '1\n' > "$VPSO_PROC_SYS_DISABLE_IPV6"

write_nginx_single_443_web_config "$tmp_dir/nginx-single-entry-web.conf"
write_nginx_reverse_proxy_conf "proxy.example.com" "40000" "n" "$tmp_dir/nginx-reverse-proxy.conf" "198.51.100.10 2001:db8::/32"
write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$tmp_dir/vpso-mux.yaml" >/dev/null
STRICT_SNI_GATE=true
write_nginx_sni_stream_config "$tmp_dir/nginx-strict-sni.conf" no
STRICT_SNI_GATE=false

diff -u tests/golden/nginx-single-entry-web.expected "$tmp_dir/nginx-single-entry-web.conf"
diff -u tests/golden/nginx-reverse-proxy.expected "$tmp_dir/nginx-reverse-proxy.conf"
diff -u tests/golden/vpso-mux.yaml.expected "$tmp_dir/vpso-mux.yaml"

assert_nginx_single_entry_web_render "$tmp_dir/nginx-single-entry-web.conf"
assert_nginx_reverse_proxy_render "$tmp_dir/nginx-reverse-proxy.conf"
assert_vpso_mux_render "$tmp_dir/vpso-mux.yaml"
assert_contains "$tmp_dir/nginx-strict-sni.conf" "    default vps_ip_reject_backend;"
assert_contains "$tmp_dir/nginx-strict-sni.conf" "    panel.example.com web_proxy_backend;"
assert_contains "$tmp_dir/nginx-strict-sni.conf" "    node.example.com vps_xray_route_0_backend;"
assert_contains "$tmp_dir/nginx-strict-sni.conf" "    reality.example.com xray_backend;"
assert_contains "$tmp_dir/nginx-strict-sni.conf" "upstream vps_ip_reject_backend {"

echo "Golden render tests passed."
