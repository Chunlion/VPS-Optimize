#!/usr/bin/env bash
set -euo pipefail
trap 'echo "golden-render failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmp_dir=$(mktemp -d /tmp/vps-golden-render.XXXXXX)
cleanup_golden_tmp() {
    [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]] || return 0
    rm -f "$tmp_dir/nginx-single-entry-web.conf"
    rm -f "$tmp_dir/nginx-reverse-proxy.conf"
    rm -f "$tmp_dir/vpso-mux.yaml"
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
TCP_ROUTE_SNIS=(tcp.example.com)
TCP_ROUTE_ADDRS=(127.0.0.1)
TCP_ROUTE_PORTS=(2443)
XRAY_SNI_ROUTE_SNIS=(node.example.com)
XRAY_SNI_ROUTE_ADDRS=(127.0.0.1)
XRAY_SNI_ROUTE_PORTS=(3443)
SNI_IP_WHITELIST_DOMAINS=(panel.example.com site.example.com)
SNI_IP_WHITELIST_RANGES=("198.51.100.10 2001:db8::/32" "203.0.113.5")
WEB_PROXY_ENGINE=nginx

VPSO_PROC_NET_IF_INET6="$tmp_dir/no-ipv6"
VPSO_PROC_SYS_DISABLE_IPV6="$tmp_dir/disable-ipv6"
printf '1\n' > "$VPSO_PROC_SYS_DISABLE_IPV6"

write_nginx_single_443_web_config "$tmp_dir/nginx-single-entry-web.conf"
write_nginx_reverse_proxy_conf "proxy.example.com" "40000" "n" "$tmp_dir/nginx-reverse-proxy.conf" "198.51.100.10 2001:db8::/32"
write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$tmp_dir/vpso-mux.yaml" >/dev/null

diff -u tests/golden/nginx-single-entry-web.expected "$tmp_dir/nginx-single-entry-web.conf"
diff -u tests/golden/nginx-reverse-proxy.expected "$tmp_dir/nginx-reverse-proxy.conf"
diff -u tests/golden/vpso-mux.yaml.expected "$tmp_dir/vpso-mux.yaml"

echo "Golden render tests passed."
