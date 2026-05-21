#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Smoke failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bash scripts/build.sh >/dev/null

assert_dist_contains() {
    local needle="$1"
    local message="${2:-Release script is missing required content: ${needle}}"
    if ! grep -Fq "$needle" dist/vps.sh; then
        echo "$message" >&2
        exit 1
    fi
}

assert_file_contains() {
    local file="$1"
    local needle="$2"
    local message="${3:-${file} is missing required content: ${needle}}"
    if ! grep -Fq -- "$needle" "$file"; then
        echo "$message" >&2
        exit 1
    fi
}

assert_file_not_contains() {
    local file="$1"
    local needle="$2"
    local message="${3:-${file} contains stale content: ${needle}}"
    if grep -Fq -- "$needle" "$file"; then
        echo "$message" >&2
        exit 1
    fi
}

assert_file_not_matches() {
    local file="$1"
    local pattern="$2"
    local message="${3:-${file} contains stale content matching: ${pattern}}"
    if grep -Eq -- "$pattern" "$file"; then
        echo "$message" >&2
        exit 1
    fi
}

assert_path_absent() {
    local path="$1"
    local message="${2:-${path} must not exist.}"
    if [[ -e "$path" ]]; then
        echo "$message" >&2
        exit 1
    fi
}

assert_function_defined_once() {
    local file="$1"
    local function_name="$2"
    local count
    count=$(grep -Ec "^${function_name}\\(\\) \\{" "$file" || true)
    if [[ "$count" != "1" ]]; then
        echo "${function_name} must be defined exactly once in ${file}; found ${count}." >&2
        exit 1
    fi
}

bash -n scripts/build.sh
bash -n vps.sh
bash -n dist/vps.sh
for module in src/*.sh; do
    bash -n "$module"
done
bash -n dog.sh
bash -n xui-custom-manager.sh
grep -q 'modules=(' scripts/build.sh
grep -q 'runtime.sh  # root/runtime guard' scripts/build.sh
grep -q 'main.sh     # bootstrap into menu wiring' scripts/build.sh
assert_file_contains scripts/build.sh 'vpso_mux_state.sh   # vpso-mux paths, engine state, and runtime status'
assert_file_contains scripts/build.sh 'vpso_mux_config.sh  # vpso-mux YAML rendering'
assert_file_contains scripts/build.sh 'vpso_mux_install.sh # vpso-mux binary/systemd helpers'
assert_file_contains scripts/build.sh 'tcp_peek_engine.sh  # TCP Peek preflight and entry-mode switching'
assert_file_contains scripts/build.sh 'firewall.sh  # firewall allow/delete/connlimit workflows'
assert_file_contains vps.sh '    firewall'
assert_dist_contains '# Module: firewall.sh' "Release script must include src/firewall.sh."
assert_dist_contains 'func_port_connlimit_menu' "Release script is missing the port connlimit menu."
assert_dist_contains 'VPSO_CONN_LIMIT_PORT_' "Release script is missing the connlimit rule marker."
assert_dist_contains 'func_save_port_connlimit_persistence' "Release script is missing the connlimit persistence save action."
assert_dist_contains 'netfilter-persistent save' "Release script must use the existing netfilter-persistent save path for connlimit persistence."
assert_dist_contains '/etc/iptables/rules.v4' "Release script must verify the IPv4 persistent rules file."
assert_file_contains README.md '主菜单 [8 防火墙规则管理] -> [6 端口并发连接限制] -> [5 保存/检查重启持久化]' "README must document the connlimit persistence save/check path."
assert_function_defined_once dist/vps.sh func_firewall_manage
build_order=$(awk '/^[[:space:]]+[a-z0-9_]+\.sh/{print $1}' scripts/build.sh | tr '\n' ' ')
case "$build_order" in
    *"sni_stack_config.sh vpso_mux_state.sh vpso_mux_config.sh vpso_mux_install.sh tcp_peek_engine.sh sni_stack_health.sh"*) ;;
    *)
        echo "vpso-mux/TCP Peek modules are not in the expected build order." >&2
        exit 1
        ;;
esac
source_order=$(awk '/^[[:space:]]+[a-z0-9_]+$/{print $1}' vps.sh | tr '\n' ' ')
case "$source_order" in
    *"sni_stack_config vpso_mux_state vpso_mux_config vpso_mux_install tcp_peek_engine sni_stack_health"*) ;;
    *)
        echo "Source checkout entrypoint vps.sh is not aligned with the vpso-mux/TCP Peek build order." >&2
        exit 1
        ;;
esac
case "$build_order" in
    *"panel_installers.sh compose_runtime.sh subscription_apps.sh subscription_compose_manage.sh subscription_service_menus.sh dockge_migration.sh panel_rescue.sh"*) ;;
    *)
        echo "Compose management modules are not in the expected build order." >&2
        exit 1
        ;;
esac
assert_file_not_contains scripts/build.sh 'subscription_tools.sh' "Release build must use the split compose/subscription modules directly."
assert_file_not_contains dist/vps.sh '# Module: subscription_tools.sh' "Release build must not include the legacy subscription_tools compatibility loader."
assert_file_not_matches src/subscription_tools.sh '^[A-Za-z_][A-Za-z0-9_]*\(\) \{' "subscription_tools.sh must stay a compatibility loader, not reintroduce duplicate implementations."
assert_file_contains src/README.md 'compose_runtime.sh`, `subscription_apps.sh`,' "Source README must document the split compose/subscription build order."
assert_file_contains src/README.md 'subscription_tools.sh` is a compatibility loader only' "Source README must document subscription_tools.sh as compatibility-only."
for module in compose_runtime.sh subscription_apps.sh subscription_compose_manage.sh subscription_service_menus.sh dockge_migration.sh; do
    assert_dist_contains "# Module: ${module}" "Release script is missing split compose/subscription module: ${module}"
done
assert_file_contains ".gitattributes" 'dist/vps.sh.sha256 text eol=lf' "dist checksum must be pinned to LF in Windows workspaces."
if grep -q $'\r' dist/vps.sh.sha256; then
    echo "dist/vps.sh.sha256 must use LF line endings." >&2
    exit 1
fi
for function_name in \
    install_docker_compose_standalone \
    ensure_docker_compose_ready \
    find_compose_file \
    is_managed_compose_dir \
    manage_compose_project \
    func_sublinkpro_menu \
    func_dockge_menu \
    func_komari_menu \
    func_update_subscription_tools \
    func_migrate_compose_to_dockge
do
    assert_function_defined_once dist/vps.sh "$function_name"
done
assert_file_contains scripts/build.sh 'sni_stack_sites.sh' "Release build must use src/sni_stack_sites.sh for 443 Web/SNI site workflows."
assert_file_contains vps.sh '    sni_stack_sites' "Source checkout entrypoint must load src/sni_stack_sites.sh for 443 Web/SNI site workflows."
assert_dist_contains '# Module: sni_stack_sites.sh' "Release script must include the active 443 Web/SNI site module."
assert_path_absent "src/sni_stack_web_sites.sh" "sni_stack_web_sites.sh is a stale shadow implementation; use src/sni_stack_sites.sh."
assert_file_not_contains scripts/build.sh 'sni_stack_web_sites.sh' "Stale sni_stack_web_sites.sh must not be added to the release build."
assert_file_not_contains vps.sh 'sni_stack_web_sites' "Source entrypoint must not load the stale sni_stack_web_sites module."
assert_file_not_contains dist/vps.sh '# Module: sni_stack_web_sites.sh' "Release script must not include the stale sni_stack_web_sites module."
assert_path_absent "src/entry_mode_cutover.sh" "entry_mode_cutover.sh is a stale shadow implementation; use src/tcp_peek_engine.sh."
assert_path_absent "src/tcp_peek_preflight.sh" "tcp_peek_preflight.sh is a stale shadow implementation; use src/tcp_peek_engine.sh."
assert_file_not_contains scripts/build.sh 'entry_mode_cutover.sh' "Stale entry-mode cutover module must not be added to the release build."
assert_file_not_contains scripts/build.sh 'tcp_peek_preflight.sh' "Stale TCP Peek preflight module must not be added to the release build."
assert_file_not_contains vps.sh 'entry_mode_cutover' "Source entrypoint must not load the stale entry-mode cutover module."
assert_file_not_contains vps.sh 'tcp_peek_preflight' "Source entrypoint must not load the stale TCP Peek preflight module."
assert_file_contains src/README.md '443/TCP Peek ownership:' "Source README must document 443/TCP Peek module ownership."
assert_file_contains src/README.md 'Do not reintroduce split shadow modules' "Source README must warn against stale split 443/TCP Peek modules."
if command -v go >/dev/null 2>&1; then
    GO_BIN=go
elif command -v go.exe >/dev/null 2>&1; then
    GO_BIN=go.exe
else
    echo "Go is required for vpso-mux release validation." >&2
    exit 1
fi
GOTOOLCHAIN=local "$GO_BIN" test ./...

dangerous_patterns='rm -rf|rm -r[[:space:]]|wget .*[&][&]|curl .*\|[[:space:]]*gpg|\|[[:space:]]*bash|bash[[:space:]]*<'
if grep -En "$dangerous_patterns" dist/vps.sh dog.sh; then
    echo "Dangerous shell patterns found." >&2
    exit 1
fi

source src/common.sh
vps_smoke_script_version="$SCRIPT_VERSION"
source src/ui.sh
source src/input.sh
source src/validate.sh
source src/rollback.sh
source src/backup.sh

[[ "$(trim_input "  q  ")" == "q" ]]
[[ "$(normalize_menu_choice_input "  q  ")" == "0" ]]
[[ "$(normalize_menu_choice_input " 返回 ")" == "0" ]]
choice=""
read_trimmed choice "" <<< " 返回 "
[[ "$choice" == "0" ]]
choice=""
read_trimmed choice "" <<< " Q "
[[ "$choice" == "0" ]]
is_yes "yes"
is_yes "YES"
is_yes "YeS"
if is_yes "no"; then
    echo "is_yes must not accept no." >&2
    exit 1
fi
[[ "$(normalize_domain_input " HTTPS://Panel.Example.COM:443/path ")" == "panel.example.com" ]]
declare -f func_edit_applied_config_center >/dev/null
declare -f edit_applied_config_file >/dev/null
declare -f validate_applied_config_kind >/dev/null
declare -f collect_applied_config_files >/dev/null
(
    source src/compose_runtime.sh
    source src/subscription_apps.sh
    source src/subscription_compose_manage.sh
    source src/subscription_service_menus.sh
    source src/dockge_migration.sh
    declare -f func_sublinkpro_menu >/dev/null
    declare -f func_dockge_menu >/dev/null
    declare -f func_komari_menu >/dev/null
    declare -f func_update_subscription_tools >/dev/null
    declare -f func_migrate_compose_to_dockge >/dev/null
    ensure_docker_compose_ready() { DOCKER_COMPOSE_CMD=true; }
    validate_applied_config_kind compose /tmp/vps-compose-smoke.yml >/dev/null
)
config_edit_tmp_dir=$(mktemp -d /tmp/vps-config-edit-smoke.XXXXXX)
printf '%s\n' 'node.example.com|127.0.0.1|1443' > "$config_edit_tmp_dir/routes.conf"
validate_xray_routes_file "$config_edit_tmp_dir/routes.conf"
printf '%s\n' 'node.example.com|127.0.0.1|70000' > "$config_edit_tmp_dir/routes.conf"
if validate_xray_routes_file "$config_edit_tmp_dir/routes.conf"; then
    echo "xray route validator must reject invalid ports." >&2
    exit 1
fi
printf '%s\n' '127.0.0.1 localhost' > "$config_edit_tmp_dir/hosts"
validate_hosts_file "$config_edit_tmp_dir/hosts"
printf '%s\n' 'example-host' > "$config_edit_tmp_dir/hostname"
validate_hostname_file "$config_edit_tmp_dir/hostname"
rm -f "$config_edit_tmp_dir/routes.conf"
rm -f "$config_edit_tmp_dir/hosts"
rm -f "$config_edit_tmp_dir/hostname"
rmdir "$config_edit_tmp_dir"
APT_UPDATED=1
apt_update_once
[[ "$APT_UPDATED" == "1" ]]
[[ "$(nginx_stream_listen_directives "127.0.0.1" "443")" == "    listen 127.0.0.1:443;" ]]
[[ "$(nginx_stream_listen_directives "0.0.0.0" "443" | grep -c '^    listen ')" == "2" ]]
[[ "$(nginx_stream_listen_directives "::1" "443")" == "    listen [::1]:443;" ]]
[[ "$(xui_cert_setting_key_sql_list)" == *"subcertfile"* ]]

(
    source src/caddy_proxy.sh
    nginx_proxy_tmp=$(mktemp /tmp/vps-nginx-proxy.XXXXXX)
    [[ "$(nginx_proxy_conf_path "panel.example.com")" == "/etc/nginx/conf.d/vps_proxy_panel.example.com.conf" ]]
    write_nginx_reverse_proxy_conf "panel.example.com" "40000" "n" "$nginx_proxy_tmp"
    grep -q 'server_name panel.example.com;' "$nginx_proxy_tmp"
    grep -q 'ssl_certificate /etc/caddy/certs/panel.example.com.crt;' "$nginx_proxy_tmp"
    grep -q 'proxy_pass http://127.0.0.1:40000;' "$nginx_proxy_tmp"
    write_nginx_reverse_proxy_conf "panel.example.com" "40001" "y" "$nginx_proxy_tmp"
    grep -q 'proxy_ssl_verify off;' "$nginx_proxy_tmp"
    grep -q 'proxy_pass https://127.0.0.1:40001;' "$nginx_proxy_tmp"
    write_nginx_reverse_proxy_conf "panel.example.com" "40002" "n" "$nginx_proxy_tmp" "198.51.100.10 2001:db8::/32"
    grep -q '# vps-optimize-ip-whitelist-start' "$nginx_proxy_tmp"
    grep -q 'allow 198.51.100.10;' "$nginx_proxy_tmp"
    grep -q 'allow 2001:db8::/32;' "$nginx_proxy_tmp"
    grep -q 'deny all;' "$nginx_proxy_tmp"
    [[ "$(nginx_proxy_whitelist_ranges_from_conf "$nginx_proxy_tmp")" == "198.51.100.10 2001:db8::/32" ]]
    strip_nginx_ip_whitelist_block "$nginx_proxy_tmp"
    ! grep -q '# vps-optimize-ip-whitelist-start' "$nginx_proxy_tmp"
    rm -f "$nginx_proxy_tmp"
)

(
    source src/input.sh
    source src/validate.sh
    source src/sni_stack_config.sh
    source src/sni_stack_install.sh
    nginx_sni_web_tmp=$(mktemp /tmp/vps-nginx-sni-web.XXXXXX)
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
    SITE_DOMAINS=(site.example.com dockge.example.com)
    SITE_BACKEND_ADDRS=(127.0.0.1 localhost)
    SITE_BACKEND_PORTS=(3000 5000)
    write_nginx_single_443_web_config "$nginx_sni_web_tmp"
    [[ "$(nginx_http_listen_directive "127.0.0.1" "8443")" == "    listen 127.0.0.1:8443 ssl http2;" ]]
    [[ "$(nginx_http_listen_directive "::1" "8443")" == "    listen [::1]:8443 ssl http2;" ]]
    [[ "$(format_hostport "::1" "8443")" == "[::1]:8443" ]]
    grep -Fq 'server_name panel.example.com;' "$nginx_sni_web_tmp"
    grep -Fq 'listen 127.0.0.1:8443 ssl http2;' "$nginx_sni_web_tmp"
    grep -Fq 'ssl_certificate /etc/caddy/certs/panel.example.com.crt;' "$nginx_sni_web_tmp"
    grep -Fq 'location = /sub {' "$nginx_sni_web_tmp"
    grep -Fq 'return 308 /sub/;' "$nginx_sni_web_tmp"
    grep -Fq 'location ^~ /sub/ {' "$nginx_sni_web_tmp"
    grep -Fq 'proxy_set_header X-Forwarded-Port 443;' "$nginx_sni_web_tmp"
    grep -Fq 'proxy_set_header Connection $vps_proxy_connection_upgrade;' "$nginx_sni_web_tmp"
    grep -Fq 'proxy_pass http://127.0.0.1:2096;' "$nginx_sni_web_tmp"
    grep -Fq 'proxy_pass http://127.0.0.1:40000;' "$nginx_sni_web_tmp"
    grep -Fq 'server_name site.example.com;' "$nginx_sni_web_tmp"
    grep -Fq 'ssl_certificate /etc/caddy/certs/site.example.com.crt;' "$nginx_sni_web_tmp"
    grep -Fq 'proxy_pass http://127.0.0.1:3000;' "$nginx_sni_web_tmp"
    grep -Fq 'server_name dockge.example.com;' "$nginx_sni_web_tmp"
    grep -Fq 'proxy_pass http://localhost:5000;' "$nginx_sni_web_tmp"
    [[ "$(grep -c '^server {' "$nginx_sni_web_tmp")" == "3" ]]
    rm -f "$nginx_sni_web_tmp"
)

(
    source src/sni_stack_config.sh
    source src/vpso_mux_state.sh
    source src/vpso_mux_config.sh
    source src/vpso_mux_install.sh
    source src/tcp_peek_engine.sh
    entry_mode_tmp_dir=$(mktemp -d /tmp/vps-entry-mode-smoke.XXXXXX)
    single_443_engine_state_path() { printf '%s\n' "$entry_mode_tmp_dir/443-engine.conf"; }
    get_entry_mode() { printf '%s' "${SMOKE_ENTRY_MODE:-nginx-stream}"; }

    [[ "$(normalize_entry_mode_name "nginx_stream")" == "nginx-stream" ]]
    [[ "$(normalize_entry_mode_name "xray_fallback")" == "xray-fallback" ]]
    [[ "$(normalize_entry_mode_name "tcp_peek")" == "tcp-peek" ]]
    [[ "$(entry_mode_engine_name "tcp_peek")" == "tcp-peek" ]]

    SMOKE_ENTRY_MODE="tcp-peek"
    [[ "$(single_443_current_engine)" == "tcp-peek" ]]
    printf '%s\n' "engine='tcp_peek'" > "$(single_443_engine_state_path)"
    [[ "$(single_443_current_engine)" == "tcp-peek" ]]
    printf '%s\n' "engine='nginx_stream'" > "$(single_443_engine_state_path)"
    [[ "$(single_443_current_engine)" == "nginx-stream" ]]
    printf '%s\n' "engine='xray-fallback'" > "$(single_443_engine_state_path)"
    [[ "$(single_443_current_engine)" == "xray-fallback" ]]

    initial_entry_output="$entry_mode_tmp_dir/initial-entry.out"
    select_initial_entry_mode >"$initial_entry_output" 2>&1 <<< $'3\nYeS\n'
    [[ "$ENTRY_MODE" == "nginx-stream" ]]
    grep -Fq 'TCP Peek 首次接管 443 前必须先安装/使用 Nginx Stream' "$initial_entry_output"
    grep -Fq '已选择 443 入口模式：nginx-stream' "$initial_entry_output"

    rm -f "$(single_443_engine_state_path)"
    rm -f "$initial_entry_output"
    rmdir "$entry_mode_tmp_dir"
)

(
    source src/panel_installers.sh
    clear() { :; }
    pause_after_external_script() { :; }
    detect_xui_single_443_defaults() { :; }
    print_xui_single_443_detected_defaults() { :; }
    run_remote_script() {
        CAPTURED_DESC="$1"
        CAPTURED_URL="$2"
        shift 2
        CAPTURED_ARGS="$*"
        return 0
    }

    panel_output=$(mktemp /tmp/vps-xpanel-smoke.XXXXXX)

    CAPTURED_DESC=""
    CAPTURED_URL=""
    CAPTURED_ARGS=""
    func_xpanel >"$panel_output" 2>&1 <<< $'\n'
    [[ "$CAPTURED_DESC" == "安装 3x-ui / x-ui 面板（最新版）" ]]
    [[ "$CAPTURED_URL" == "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh" ]]
    [[ -z "$CAPTURED_ARGS" ]]
    grep -Fq '最新版 3.x 安装器如果询问 SSL certificate setup method，请选择 Skip SSL / 不申请 SSL' "$panel_output"

    CAPTURED_DESC=""
    CAPTURED_URL=""
    CAPTURED_ARGS=""
    func_xpanel >"$panel_output" 2>&1 <<< $'2\n'
    [[ "$CAPTURED_DESC" == "安装 3x-ui / x-ui 面板（v2.9.4）" ]]
    [[ "$CAPTURED_URL" == "https://raw.githubusercontent.com/mhsanaei/3x-ui/v2.9.4/install.sh" ]]
    [[ "$CAPTURED_ARGS" == "v2.9.4" ]]
    grep -Fq 'v2.9.4 属于 2.x 老流程' "$panel_output"

    rm -f "$panel_output"
)

remote_tmp_dir=$(mktemp -d /tmp/vps-remote-smoke.XXXXXX)
remote_script="$remote_tmp_dir/remote.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo remote-run-ok' > "$remote_script"
remote_output=$(run_remote_script "smoke remote script" "file://$remote_script")
[[ "$remote_output" == *"remote-run-ok"* ]]
rm -f "$remote_script"
rmdir "$remote_tmp_dir"

legacy_tmp_dir=$(mktemp -d /tmp/vps-legacy-smoke.XXXXXX)
legacy_entry="$legacy_tmp_dir/vps.sh"
legacy_release="$legacy_tmp_dir/release.sh"
cp vps.sh "$legacy_entry"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'func_sni_stack_quick_menu() { :; }' \
    'main_menu() { :; }' \
    'echo legacy-fallback-ok' > "$legacy_release"
sed -i "s#^RELEASE_URL=.*#RELEASE_URL=\"file://$legacy_release\"#" "$legacy_entry"
legacy_output=$(bash "$legacy_entry" 2>&1)
[[ "$legacy_output" == *"legacy-fallback-ok"* ]]
grep -q 'legacy-fallback-ok' "$legacy_entry"
rm -f "$legacy_entry"
rm -f "$legacy_release"
rmdir "$legacy_tmp_dir"

source <(sed -n '1,/^show_port_list()/p' dog.sh | sed '$d')
[[ "$(normalize_main_choice " add ")" == "1" ]]
[[ "$(normalize_main_choice "tg")" == "7" ]]
[[ "$(normalize_main_choice "q")" == "0" ]]
[[ "$(format_bytes "")" == "0B" ]]
[[ "$(format_bytes 1023)" == "1023B" ]]
declare -f sanitize_nftables_config >/dev/null
declare -f update_telegram_config >/dev/null

grep -q 'MODULES=(' vps.sh
grep -q 'src/${module}.sh' vps.sh
grep -q 'VPS 全能控制面板' vps.sh
grep -q 'RELEASE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh"' vps.sh
if grep -Eq '^[[:space:]]*(source|\.)[[:space:]]+.*src/' dist/vps.sh; then
    echo "Release script must not source src modules at runtime." >&2
    exit 1
fi
if grep -Eq '确认下载并执行该远程脚本|如仍要执行，请输入 YES' dist/vps.sh; then
    echo "Remote script runner must not prompt for an extra execution confirmation." >&2
    exit 1
fi
grep -q 'func_sni_stack_quick_menu' dist/vps.sh
grep -q 'manage_sni_stack_tcp_routes' dist/vps.sh
grep -q 'TCP_ROUTE_SNIS_CSV' dist/vps.sh
grep -q 'single_443_current_engine' dist/vps.sh
assert_file_contains "src/xray_sni_routes.sh" 'Xray 入站管理' "Xray inbound menu must use the current menu name."
assert_file_not_contains "src/xray_sni_routes.sh" '443 TCP/SNI 本地入站管理' "Xray inbound menu must not use the old TCP/SNI title."
assert_file_contains "src/xray_sni_routes.sh" '用于当前支持的单入口模式渲染分流规则' "Xray inbound menu must describe route records as entry-mode render input."
assert_file_not_contains "src/xray_sni_routes.sh" '只写 Nginx stream SNI -> 本地端口规则' "Xray inbound menu must not describe route records as nginx-stream-only."
assert_file_contains "src/xray_route_state.sh" 'fallback 普通 HTTPS 到所选 Web 反代引擎' "xray-fallback explanation must mention the selected Web reverse proxy engine."
assert_file_not_contains "src/xray_route_state.sh" 'fallback 普通 HTTPS 到 Caddy' "xray-fallback explanation must not hard-code Caddy."
assert_dist_contains 'Xray 入站管理' 'Release script must include the current Xray inbound menu name.'
assert_file_not_contains "dist/vps.sh" '443 TCP/SNI 本地入站管理' "Release script must not use the old TCP/SNI title."
assert_dist_contains '用于当前支持的单入口模式渲染分流规则' 'Release script must describe Xray inbound records as entry-mode render input.'
assert_file_not_contains "dist/vps.sh" '只写 Nginx stream SNI -> 本地端口规则' "Release script must not describe Xray inbound records as nginx-stream-only."
assert_dist_contains 'fallback 普通 HTTPS 到所选 Web 反代引擎' 'Release script must describe xray-fallback as using the selected Web reverse proxy engine.'
assert_file_not_contains "dist/vps.sh" 'fallback 普通 HTTPS 到 Caddy' "Release script must not hard-code Caddy in xray-fallback explanation."
for function_name in \
    normalize_entry_mode_name \
    entry_mode_engine_name \
    entry_mode_expected_listener \
    preflight_tcppeek_before_cutover \
    preflight_entry_mode_before_cutover \
    switch_entry_mode
do
    assert_function_defined_once dist/vps.sh "$function_name"
done
assert_file_not_matches src/tcp_peek_engine.sh '^entry_mode_expected_listener\(\)' "entry_mode_expected_listener belongs to shared 443 state/listener helpers, not the TCP Peek engine module."
for function_name in \
    vpso_mux_config_path \
    vpso_mux_service_name \
    vpso_mux_status_json_path \
    single_443_engine_state_path \
    yaml_quote \
    single_443_current_engine \
    sni_stack_route_name \
    sni_stack_route_summary_for_state \
    sni_stack_whitelist_summary_for_state \
    write_single_443_engine_state \
    show_single_443_engine_status \
    show_tcp_peek_splice_info \
    print_vpso_mux_systemd_fallback_status \
    print_vpso_mux_status_json \
    show_vpso_mux_runtime_status \
    append_vpso_mux_route_yaml \
    write_vpso_mux_config_from_sni_stack \
    generate_tcp_peek_config \
    go_install_vpso_mux_latest \
    vpso_mux_build_resource_check \
    require_vpso_mux_binary_for_cutover \
    install_vpso_mux_binary \
    write_vpso_mux_systemd_service \
    run_vpso_mux_config_check \
    print_vpso_mux_failure_context
do
    assert_function_defined_once dist/vps.sh "$function_name"
    assert_file_not_matches src/tcp_peek_engine.sh "^${function_name}\\(\\)" "src/tcp_peek_engine.sh must not keep duplicate ${function_name}."
done
grep -q 'write_single_443_engine_state "nginx-stream"' dist/vps.sh
grep -q 'write_single_443_engine_state "tcp-peek"' dist/vps.sh
grep -q 'write_single_443_engine_state "xray-fallback"' dist/vps.sh
grep -q 'entry_mode_engine_name()' dist/vps.sh
grep -q 'echo "$mode"' dist/vps.sh
if grep -q 'write_single_443_engine_state "nginx_stream"' dist/vps.sh || grep -q 'write_single_443_engine_state "tcp_peek"' dist/vps.sh || grep -q 'write_single_443_engine_state "xray_fallback"' dist/vps.sh; then
    echo "443 engine state must write canonical hyphenated mode names." >&2
    exit 1
fi
grep -q 'generate_tcp_peek_config' dist/vps.sh
assert_file_not_contains 'dist/vps.sh' 'switch_public_443_to_tcp_peek' 'TCP Peek-specific cutover wrapper must be removed; use the [5] entry-mode switch instead.'
assert_file_not_contains 'dist/vps.sh' 'rollback_tcp_peek_to_nginx_stream' 'TCP Peek-specific rollback wrapper must be removed; use the broader [7] rollback instead.'
grep -q 'sni_stack_health_check_enhanced' dist/vps.sh
grep -q 'vpso-mux.service' dist/vps.sh
grep -q 'vpso-mux-preflight.service' dist/vps.sh
grep -q 'go_install_vpso_mux_latest' dist/vps.sh
grep -q 'GOTOOLCHAIN=local' dist/vps.sh
grep -q '拒绝在生产机上自动下载临时 Go 工具链' dist/vps.sh
assert_dist_contains 'go build -p 1 -o /usr/local/bin/vpso-mux github.com/Chunlion/VPS-Optimize/cmd/vpso-mux' 'Release script must build the vpso-mux command package.'
assert_dist_contains 'ExecStart=/usr/local/bin/vpso-mux -config /etc/vps-optimize/vpso-mux.yaml' 'Release script must install the public vpso-mux systemd entry.'
assert_dist_contains 'ExecStart=/usr/local/bin/vpso-mux -config /etc/vps-optimize/vpso-mux.preflight.yaml' 'Release script must install the TCP Peek 8444 preflight systemd entry.'
assert_dist_contains 'run_tcppeek_preflight_service 0 "8444" || return 1' 'TCP Peek cutover must still run the 8444 preflight before touching public 443.'
assert_dist_contains 'write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$tmp_config" || return 1' 'TCP Peek cutover must render vpso-mux config from the shared 443 stack.'
if grep -q 'go1.23.0 download' dist/vps.sh; then
    echo "TCP Peek cutover must not download a temporary Go toolchain." >&2
    exit 1
fi
grep -q 'replace golang.org/x/sys => golang.org/x/sys v0.30.0' dist/vps.sh
grep -q 'go mod download github.com/Chunlion/VPS-Optimize' dist/vps.sh
grep -q 'VPS-Optimize-src' dist/vps.sh
grep -q '检测到远程 vpso-mux 旧源码' dist/vps.sh
grep -q 'int(remaining)' dist/vps.sh
grep -q 'replace github.com/Chunlion/VPS-Optimize => ./VPS-Optimize-src' dist/vps.sh
grep -q 'go build -p 1 -o /usr/local/bin/vpso-mux' dist/vps.sh
grep -q 'require_vpso_mux_binary_for_cutover' dist/vps.sh
grep -q 'preflight_tcppeek_before_cutover' dist/vps.sh
grep -q 'guard_current_ssh_not_on_entry_port' dist/vps.sh
grep -q 'TCP Peek 8444 预检' dist/vps.sh
grep -q 'preview_entry_mode_cutover' dist/vps.sh
grep -q '443 单入口切换变更预览' dist/vps.sh
grep -q 'vpso_mux_status_json_path' dist/vps.sh
grep -q '/var/lib/vps-optimize/vpso-mux/status.json' dist/vps.sh
grep -q 'show_vpso_mux_runtime_status' dist/vps.sh
grep -Fq '5) switch_entry_mode "tcp-peek" ;;' dist/vps.sh
grep -Fq '7) rollback_last_entry_mode ;;' dist/vps.sh
grep -Fq 'TCP Peek 首次接管 443 前必须先安装/使用 Nginx Stream' dist/vps.sh
grep -Fq '是否先安装/使用 Nginx Stream 完成本次首次安装？(Y/n，默认 yes):' dist/vps.sh
assert_file_not_contains 'dist/vps.sh' '19. 切换公网 443 到 TCP Peek + Splice 模式' '443 menu must not expose a redundant TCP Peek-specific cutover entry.'
assert_file_not_contains 'dist/vps.sh' '19) switch_public_443_to_tcp_peek ;;' '443 menu must not dispatch to a removed TCP Peek-specific cutover wrapper.'
assert_file_not_contains 'dist/vps.sh' '20. 从 TCP Peek 回滚到 Nginx Stream 模式' '443 menu must not expose a redundant TCP Peek-specific rollback entry.'
assert_file_not_contains 'dist/vps.sh' '20) rollback_tcp_peek_to_nginx_stream ;;' '443 menu must not dispatch to a removed TCP Peek-specific rollback wrapper.'
while IFS='|' read -r menu_no menu_label case_action; do
    [[ -n "$menu_no" ]] || continue
    if ! grep -Fq " ${menu_no}. ${menu_label}" dist/vps.sh; then
        echo "443 single-entry menu item ${menu_no} label is missing or changed." >&2
        exit 1
    fi
    if ! grep -Fq "${menu_no}) ${case_action}" dist/vps.sh; then
        echo "443 single-entry menu item ${menu_no} dispatch no longer matches its label." >&2
        exit 1
    fi
done <<'SNI_MENU_MAP'
11|443 链路体检|sni_stack_health_check_enhanced ;;
12|443 网络访问测试|func_443_network_test; continue ;;
13|CF DNS / Caddy 证书维护|func_caddy_cf_maintenance_menu; continue ;;
14|修改 443 共享参数|edit_sni_stack_runtime_profile; continue ;;
15|订阅链接 / External Proxy 提示|check_sni_stack_subscription_hint ;;
16|查看 TCP Peek + Splice 状态 / 8444 预检|start_tcp_peek_test_port ;;
17|TCP Peek 分流规则校验|tcp_peek_dry_run_config ;;
18|查看 TCP Peek + Splice 日志|view_vpso_mux_logs ;;
SNI_MENU_MAP

docs_menu_files=(
    ".github/ISSUE_TEMPLATE/bug_report.md"
    "README.md"
    "docs/443-single-entry.md"
    "docs/443-tcp-peek-engine.md"
    "docs/443-single-entry-troubleshooting.md"
    "docs/config-paths.md"
    "docs/existing-server-migration.md"
    "docs/recovery-runbook.md"
    "tutorials/02-3x-ui-reality-443.md"
    "tutorials/03-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md"
)
for file in "${docs_menu_files[@]}"; do
    assert_file_not_contains "$file" '主菜单 [18 443 单入口管理中心]' "${file} must not point users to the old main menu [18] 443 entry."
    assert_file_not_contains "$file" '主菜单 [14 服务健康总览]' "${file} must not point users to the old main menu [14] health entry."
    assert_file_not_contains "$file" '[15 配置备份与回滚]' "${file} must not point users to the old backup menu [15]."
done
assert_file_not_contains "docs/443-single-entry.md" '主菜单 [3] -> [13] Caddy 反代' "443 tutorial must not point users to the old Caddy menu path."
assert_file_not_contains "docs/443-single-entry.md" '[19] -> [2] -> [5]' "443 tutorial must not point Web whitelist users to the old nested whitelist path."

tcp_peek_doc_files=(
    "README.md"
    "docs/443-single-entry.md"
    "docs/443-tcp-peek-engine.md"
)
for file in "${tcp_peek_doc_files[@]}"; do
    assert_file_not_matches "$file" '进阶(模式|实现|可选模式)' "${file} must not describe TCP Peek as an advanced mode."
    assert_file_not_contains "$file" '[19] 切换公网 443 到 TCP Peek + Splice 模式' "${file} should use the existing [5] entry-mode switch instead of a redundant [19] TCP Peek cutover."
    assert_file_not_contains "$file" '-> [19] 切换公网 443 到 TCP Peek + Splice 模式' "${file} should not list the removed [19] TCP Peek cutover entry."
    assert_file_not_contains "$file" '[20] 从 TCP Peek 回滚到 Nginx Stream 模式' "${file} should prefer the broader [7] rollback path over the TCP Peek-specific rollback entry."
    assert_file_not_contains "$file" 'TCP Peek 专用回滚' "${file} should not recommend a TCP Peek-specific rollback path."
done

assert_file_contains "README.md" '配置过程和 Nginx Stream 一样' "README must explain that TCP Peek uses the same configuration flow as Nginx Stream."
assert_file_contains ".github/ISSUE_TEMPLATE/bug_report.md" '主菜单 [19 443 单入口管理中心] -> [2 首次配置 / 安装 443 单入口]' "Bug report template must show the current 443 menu path."
assert_file_contains ".github/ISSUE_TEMPLATE/bug_report.md" '主菜单 [15 服务健康总览]' "Bug report template must show the current health menu path."
assert_file_contains "README.md" '正式切换使用 `[5] 切换到 TCP Peek + Splice 模式`' "README must point TCP Peek formal cutover at the existing entry-mode switch [5]."
assert_file_contains "README.md" '[7] 回滚上一次入口模式切换' "README must point rollback guidance at the broader entry-mode rollback [7]."
assert_file_contains "docs/443-single-entry.md" 'TCP Peek 的优点' "443 tutorial must list TCP Peek advantages."
assert_file_contains "docs/443-single-entry.md" '配置过程和 Nginx Stream 一样' "443 tutorial must say TCP Peek uses the same configuration flow."
assert_file_contains "docs/443-single-entry.md" '主菜单 [19 443 单入口管理中心] -> [5 切换到 TCP Peek + Splice 模式]' "443 tutorial must show the existing TCP Peek cutover entry [5]."
assert_file_contains "docs/443-single-entry.md" '主菜单 [19 443 单入口管理中心] -> [7 回滚上一次入口模式切换]' "443 tutorial must point rollback guidance at the broader entry-mode rollback [7]."
assert_file_contains "docs/443-tcp-peek-engine.md" 'TCP Peek 的主要优点' "TCP Peek engine doc must list TCP Peek advantages."
assert_file_contains "docs/443-tcp-peek-engine.md" '配置过程和 Nginx Stream 一样' "TCP Peek engine doc must say TCP Peek uses the same configuration flow."
assert_file_contains "docs/443-tcp-peek-engine.md" '  -> [5] 切换到 TCP Peek + Splice 模式' "TCP Peek engine doc must show the existing cutover entry [5]."
assert_file_contains "docs/443-tcp-peek-engine.md" '  -> [7] 回滚上一次入口模式切换' "TCP Peek engine doc must point rollback guidance at the broader entry-mode rollback [7]."

single_entry_mode_doc_files=(
    "README.md"
    "docs/443-single-entry-troubleshooting.md"
    "docs/config-paths.md"
    "tutorials/02-3x-ui-reality-443.md"
)
for file in "${single_entry_mode_doc_files[@]}"; do
    assert_file_not_contains "$file" '公网 `443` 应只由 Nginx stream 监听' "${file} must not describe Nginx stream as the only possible public 443 listener."
    assert_file_not_contains "$file" '公网 `443` 只应由 Nginx stream 监听' "${file} must not describe Nginx stream as the only possible public 443 listener."
    assert_file_not_contains "$file" '公网 `443` 只给 Nginx stream' "${file} must not describe Nginx stream as the only possible public 443 listener."
    assert_file_not_contains "$file" '公网 `443` 只交给 Nginx stream' "${file} must not describe Nginx stream as the only possible public 443 listener."
done
assert_file_not_contains "tutorials/02-3x-ui-reality-443.md" '| Nginx 公网监听地址 |' "3x-ui REALITY tutorial must not show Nginx as the fixed public 443 listener."
assert_file_not_contains "tutorials/02-3x-ui-reality-443.md" '| 公网 `443` | Nginx stream 监听 |' "3x-ui REALITY tutorial must not expect public 443 to always be Nginx stream."
assert_file_not_contains "docs/443-single-entry.md" '默认 Nginx Stream 架构是：' "443 tutorial opening must describe the current entry-mode model, not the old Nginx-only default diagram."
assert_file_not_contains "docs/443-single-entry.md" '公网 443 -> Nginx stream 按 SNI 分流' "443 tutorial opening must not show Nginx stream as the fixed public 443 path."
assert_file_contains "docs/443-single-entry.md" '公网 443 -> 当前 ENTRY_MODE 对应的单个入口服务' "443 tutorial opening must show the current single-listener entry-mode chain."
assert_file_not_contains "docs/443-single-entry.md" 'Caddy 监听：127.0.0.1:8443' "443 tutorial examples must not pin the local Web reverse proxy listener to Caddy."
assert_file_not_contains "tutorials/02-3x-ui-reality-443.md" 'panel.example.com  -> Caddy 127.0.0.1:8443' "3x-ui REALITY tutorial must not pin panel Web backend to Caddy 127.0.0.1:8443."
assert_file_not_contains "tutorials/02-3x-ui-reality-443.md" 'panel.example.com/sub/ -> Caddy ->' "3x-ui REALITY tutorial must not pin subscription Web backend to Caddy."
assert_file_contains "tutorials/02-3x-ui-reality-443.md" 'panel.example.com  -> 当前 Web 反代引擎（Caddy 或 Nginx，例如 127.0.0.1:8443）' "3x-ui REALITY tutorial must describe the selectable local Web reverse proxy engine."
assert_file_contains "tutorials/02-3x-ui-reality-443.md" '如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，脚本只在兼容读取旧配置时按 `nginx-stream` 处理' "3x-ui REALITY tutorial must document ENTRY_MODE fallback compatibility."
assert_file_contains "README.md" '如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，按 `nginx-stream` 兼容读取' "README must document ENTRY_MODE fallback compatibility."
assert_file_contains "docs/config-paths.md" '如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，脚本按 `nginx-stream` 兼容读取' "Config paths doc must document ENTRY_MODE fallback compatibility."
assert_file_contains "docs/443-single-entry-troubleshooting.md" '公网 `443` 只应由当前 `ENTRY_MODE` 对应的单个入口服务监听' "Troubleshooting doc must describe the current entry-mode listener model."
grep -q 'print_vpso_mux_failure_context' dist/vps.sh
grep -q 'print_nginx_stream_failure_context' dist/vps.sh
grep -q 'assert_nginx_stream_config_loaded' dist/vps.sh
grep -q 'listener_info_has_entry' dist/vps.sh
grep -q 'listener_info_has_entry "$listener" "xray"' dist/vps.sh
grep -q 'listener_info_has_entry "$listener" "nginx"' dist/vps.sh
grep -q 'listener_info_has_entry "$listener" "tcppeek"' dist/vps.sh
grep -q 'listener=$(detect_443_listener "$NGINX_LISTEN_PORT")' dist/vps.sh
grep -q 'for ((i = 1; i <= tries; i++)); do' dist/vps.sh
grep -q 'stop_vpso_mux_services_for_restore' dist/vps.sh
grep -q 'systemctl stop vpso-mux-preflight' dist/vps.sh
grep -q 'tcp_probe_once' dist/vps.sh
grep -q 'local_listen_socket_matches_probe "$host" "$port"' dist/vps.sh
grep -q 'is_loopback_probe_host "$host"' dist/vps.sh
grep -q 'Xray/REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1' dist/vps.sh
grep -q 'nginx -T .*grep -Fq "$conf_file"' dist/vps.sh
grep -q 'apply_nginx_stream_mode "$backup_dir"' dist/vps.sh
grep -q 'local current_mode backup_dir planned_backup_dir assume_yes' dist/vps.sh
grep -q 'if \[\[ "$assume_yes" != "--yes" \]\]; then' dist/vps.sh
grep -q 'if ! restart_service_if_available nginx; then' dist/vps.sh
grep -q 'stop_vpso_mux_service_if_public_443 || return 1' dist/vps.sh
grep -q 'stop_xray_entry_service_if_public_443 || return 1' dist/vps.sh
grep -q 'Xray 仍在监听公网 443' dist/vps.sh
grep -q 'nginx 服务仍在运行，但已不监听公网 ${NGINX_LISTEN_PORT}' dist/vps.sh
grep -q 'if ! stop_public_443_entry_services_for_target "$old_mode"; then' dist/vps.sh
grep -q 'if ! apply_entry_mode_by_name "$old_mode" "$backup_dir"; then' dist/vps.sh
grep -q 'backup_dir=$(backup_entry_mode_config) || return 1' dist/vps.sh
grep -q 'issue_and_install_cert_for_domain "$PANEL_DOMAIN" "$CF_TOKEN" || { rollback_sni_stack_after_failure "$backup_dir"' dist/vps.sh
grep -q 'issue_and_install_cert_for_domain "$site_domain" "$CF_TOKEN" || { rollback_sni_stack_after_failure "$backup_dir"' dist/vps.sh
grep -q 'preflight_entry_mode_before_cutover "$ENTRY_MODE" || { rollback_sni_stack_after_failure "$backup_dir"' dist/vps.sh
if awk '/if \[\[ "\$NGINX_LISTEN_ADDR" == "0\.0\.0\.0" \]\]/{flag=1; next} /elif \[\[ "\$NGINX_LISTEN_ADDR" == "::" \]\]/{flag=0} flag {print}' dist/vps.sh | grep -q '\[::\]:\${listen_port}'; then
    echo "vpso-mux must not emit both 0.0.0.0 and [::] listeners for one public port." >&2
    exit 1
fi
grep -q 'golang.org/x/sys v0.30.0' go.mod
if grep -q 'golang.org/x/sys v0.31.0' go.mod; then
    echo "vpso-mux must stay installable with Go 1.22 from common distro packages." >&2
    exit 1
fi
grep -q 'func_443_network_test' dist/vps.sh
grep -q 'func_docker_443_exposure_audit' dist/vps.sh
grep -q 'func_docker_project_status' dist/vps.sh
grep -q 'print_project_runtime_overview' dist/vps.sh
grep -q 'xui_panel_status_compact' dist/vps.sh
grep -q '3x-ui面板' dist/vps.sh
grep -Fq '安装 3x-ui / x-ui 面板（最新版）' dist/vps.sh
grep -Fq 'https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh' dist/vps.sh
grep -Fq '最新版 3.x 安装器如果询问 SSL certificate setup method，请选择 Skip SSL / 不申请 SSL' dist/vps.sh
grep -Fq '安装 3x-ui / x-ui 面板（v2.9.4）' dist/vps.sh
grep -Fq 'https://raw.githubusercontent.com/mhsanaei/3x-ui/v2.9.4/install.sh' dist/vps.sh
grep -Fq 'install_args=("v2.9.4")' dist/vps.sh
grep -Fq 'v2.9.4 属于 2.x 老流程' dist/vps.sh
grep -Fq '管理 S-UI 面板' dist/vps.sh
grep -Fq '安装 S-UI 面板' dist/vps.sh
grep -Fq 'https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh' dist/vps.sh
if grep -q 'x-ui\[$(service_status_compact x-ui)\]' dist/vps.sh; then
    echo "Health overview must not show x-ui as a separate installed product." >&2
    exit 1
fi
grep -q 'print_auto_update_notice' dist/vps.sh
grep -q 'func_traffic_guard_menu' dist/vps.sh
grep -q 'install_traffic_guard_checker' dist/vps.sh
grep -q 'vps-traffic-guard.timer' dist/vps.sh
grep -q 'TRAFFIC_GUARD_CONFIG=' dist/vps.sh
grep -q 'traffic_guard_detect_initial_used_bytes' dist/vps.sh
grep -q 'traffic_guard_write_state_baseline' dist/vps.sh
grep -q '本次重新配置默认按当前网卡累计估算' dist/vps.sh
grep -q 'traffic_guard_gb_to_bytes_zero_ok' dist/vps.sh
grep -q 'traffic_guard_cycle_date_for_month' dist/vps.sh
grep -q 'cycle_date_for_month' dist/vps.sh
grep -q '每月套餐/账单重置日 1-31' dist/vps.sh
grep -q 'guard_exit()' dist/vps.sh
grep -q 'checker exited unexpectedly rc=' dist/vps.sh
grep -q 'reset_traffic_guard_failed_state' dist/vps.sh
grep -q 'systemctl reset-failed vps-traffic-guard.service vps-traffic-guard.timer' dist/vps.sh
grep -q 'poweroff command failed; will retry on next timer run' dist/vps.sh
if grep -q '重置日只支持 1-28' dist/vps.sh; then
    echo "Traffic guard reset day must support 1-31." >&2
    exit 1
fi
grep -q 'counter reset detected on ${IFACE}, baseline reset and preserved' dist/vps.sh
grep -q 'traffic|quota|bill|流量|达量|账单) echo "10"' dist/vps.sh
if grep -q '20\..*流量达量关机保护' dist/vps.sh; then
    echo "Traffic guard must stay in the network submenu, not the main menu." >&2
    exit 1
fi
grep -q 'curl_rc=' dist/vps.sh
if grep -q 'HTTP ${code}${PLAIN}' dist/vps.sh && grep -q '|| echo "000"' dist/vps.sh; then
    echo "443 curl probe must not concatenate fallback HTTP 000 values." >&2
    exit 1
fi
awk "/<<'GUARD_SCRIPT'/{flag=1; next} /^GUARD_SCRIPT$/{flag=0} flag {print}" dist/vps.sh | bash -n
grep -q 'func_health_dashboard' dist/vps.sh
grep -q 'func_backup_center' dist/vps.sh
grep -q 'func_edit_applied_config_center' dist/vps.sh
grep -q 'edit_applied_config_file' dist/vps.sh
grep -q 'collect_applied_config_files' dist/vps.sh
grep -q 'validate_applied_config_kind' dist/vps.sh
grep -q '5. 查看/编辑脚本已应用配置' dist/vps.sh
grep -q 'func_hosts_manage' dist/vps.sh
grep -q 'hosts_add_or_update_entry' dist/vps.sh
grep -q 'func_ssh_security_menu' dist/vps.sh
grep -q 'func_ssh_login_mode_menu' dist/vps.sh
grep -q 'ssh_apply_auth_mode' dist/vps.sh
grep -q 'ssh_prepare_runtime_dir' dist/vps.sh
grep -q 'ssh_write_sshd_port_dropin' dist/vps.sh
grep -q 'ssh_write_auth_dropin' dist/vps.sh
grep -q 'ssh_reconcile_cloud_auth_dropins' dist/vps.sh
grep -q 'ssh_assert_auth_mode_effective' dist/vps.sh
grep -q 'ssh_restart_runtime' dist/vps.sh
grep -q 'sshd_config.d/00-vps-optimize-port.conf' dist/vps.sh
grep -q 'sshd_config.d/00-vps-optimize-auth.conf' dist/vps.sh
grep -q 'VPS-Optimize reconciled cloud image setting' dist/vps.sh
grep -q '50-cloud-init.conf' dist/vps.sh
grep -q 'for unit in ssh.socket sshd.socket' dist/vps.sh
grep -q 'func_network_interface_manage' dist/vps.sh
grep -q 'network_set_iface_mtu' dist/vps.sh
grep -q '4) func_caddy_reverse_proxy_menu' dist/vps.sh
grep -q 'nginx|ngx|proxy|reverse' dist/vps.sh
grep -q 'func_nginx_add_reverse_proxy' dist/vps.sh
grep -q '2) func_nginx_add_reverse_proxy ;;' dist/vps.sh
grep -q 'func_proxy_add_insecure' dist/vps.sh
grep -q 'func_nginx_add_insecure' dist/vps.sh
grep -q 'func_proxy_manage_ip_whitelist' dist/vps.sh
grep -q 'func_nginx_manage_ip_whitelist' dist/vps.sh
grep -q 'func_proxy_clear_config' dist/vps.sh
grep -q 'func_nginx_clear_proxy_config' dist/vps.sh
grep -q 'nginx_ip_whitelist_block' dist/vps.sh
grep -q '后端 HTTPS 跳过证书校验' dist/vps.sh
grep -q '域名 IP 白名单' dist/vps.sh
grep -q '清空反代配置' dist/vps.sh
grep -q 'func_edit_applied_proxy_config' dist/vps.sh
grep -q '6) func_edit_applied_proxy_config ;;' dist/vps.sh
grep -q 'collect_editable_proxy_config_files' dist/vps.sh
grep -q 'validate_proxy_config_kind' dist/vps.sh
grep -q 'reload_proxy_config_kind' dist/vps.sh
grep -q 'nginx_proxy_warn_if_single_entry_enabled' dist/vps.sh
grep -q 'quarantine_legacy_nginx_https_proxy_configs' dist/vps.sh
grep -q 'write_nginx_reverse_proxy_conf' dist/vps.sh
grep -q '/etc/nginx/conf.d/vps_proxy_${domain}.conf' dist/vps.sh
grep -q '/etc/nginx/conf.d/00-vps-proxy-map.conf' dist/vps.sh
grep -q 'issue_and_install_cert_for_domain "$domain" "$CF_TOKEN"' dist/vps.sh
grep -q 'systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx' dist/vps.sh
grep -q 'vps-optimize-ip-whitelist-start' dist/vps.sh
grep -q 'allow ${range};' dist/vps.sh
grep -q '/etc/vps-optimize/quarantine/nginx-proxy' dist/vps.sh
grep -q 'WEB_PROXY_ENGINE' dist/vps.sh
grep -q 'normalize_web_proxy_engine' dist/vps.sh
grep -q 'write_nginx_single_443_web_config' dist/vps.sh
grep -q 'apply_web_proxy_configs_for_single_443' dist/vps.sh
grep -q 'switch_sni_stack_web_proxy_engine' dist/vps.sh
grep -q 'vps_sni_web_${CADDY_LISTEN_PORT}.conf' dist/vps.sh
grep -q 'xray-fallback + Nginx 本地 Web 反代' dist/vps.sh
grep -q '4. 查看/编辑 Compose 配置' dist/vps.sh
grep -q 'edit_applied_config_file "$compose_file" "compose"' dist/vps.sh
assert_file_contains "README.md" '主菜单 [16 配置备份与回滚] -> [5 查看/编辑脚本已应用配置]' "README must document the global applied-config editor."
assert_file_contains "docs/config-paths.md" '主菜单 [16 配置备份与回滚] -> [5 查看/编辑脚本已应用配置]' "Config paths doc must list the global applied-config editor."
assert_file_contains "README.md" '[4 反代] 里的后端 HTTPS 跳过证书校验、域名 IP 白名单、查看/编辑已应用配置和清空反代配置都同时提供 Caddy/Nginx 入口' "README must document Nginx parity in the reverse proxy menu."
assert_file_contains "README.md" '443 单入口下的 Web 反代引擎可以选择 Caddy 或 Nginx' "README must document selectable Web proxy engines in 443 single-entry."
assert_file_contains "README.md" 'xray-fallback + Nginx 本地 Web 反代' "README must warn about the unsupported whitelist combination."
assert_file_contains "docs/443-single-entry.md" '[4] -> [5 域名 IP 白名单]' "443 doc must describe the combined Caddy/Nginx whitelist menu."
assert_file_contains "docs/443-single-entry.md" '[8 切换 Web 反代引擎]' "443 doc must document switching the Web reverse proxy engine."
assert_file_contains "docs/443-single-entry.md" 'Nginx 本地 Web 反代 | 不允许新增或覆盖 Web 白名单' "443 doc must prohibit unsupported Nginx fallback whitelist usage."
assert_file_contains "docs/443-tcp-peek-engine.md" 'Web 反代引擎可选择 Caddy 或 Nginx' "TCP Peek doc must describe the shared Caddy/Nginx Web proxy engine."
assert_file_contains "README.md" 'Nginx 反代会直接监听公网 80/443' "README must explain the non-single-entry Nginx HTTPS reverse proxy behavior."
subscription_public_hint='公网 HTTPS 访问建议：未启用 443 单入口时，请走主菜单 [4 反代] 里的 Caddy 或 Nginx HTTPS 反代；已启用 443 单入口时，请走主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]。'
assert_file_contains "src/subscription_apps.sh" "$subscription_public_hint" "Subscription/Komari installers must explain both non-single-entry and 443 single-entry reverse proxy paths."
assert_dist_contains "$subscription_public_hint" "Release script must include the current Subscription/Komari public HTTPS guidance."
panel_public_hint='提示：面板或订阅工具对外访问，未启用 443 单入口时走主菜单 [4 反代] 里的 Caddy 或 Nginx HTTPS 反代；已启用 443 单入口时走主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] 统一管理。'
assert_file_contains "src/menus.sh" "$panel_public_hint" "Panel/tools menu must explain both non-single-entry and 443 single-entry reverse proxy paths."
assert_dist_contains "$panel_public_hint" "Release script must include the current panel/tools public HTTPS guidance."
panel_help_public_hint='5/6/7/8 管理订阅工具和 Dockge，部署后公网 HTTPS 访问：未启用 443 单入口时走主菜单 [4 反代] 里的 Caddy 或 Nginx HTTPS 反代；已启用 443 单入口时走主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]。'
assert_file_contains "src/menus.sh" "$panel_help_public_hint" "Panel/tools help must explain both non-single-entry and 443 single-entry reverse proxy paths."
assert_dist_contains "$panel_help_public_hint" "Release script must include the current panel/tools help public HTTPS guidance."
subscription_internal_port_hint='该端口只给当前本地 Web 反代引擎（${web_label}）访问，不应写成公网订阅入口。'
assert_file_contains "src/sni_stack_health.sh" "$subscription_internal_port_hint" "Subscription hint must describe the internal subscription port as current Web reverse proxy engine-only."
assert_dist_contains "$subscription_internal_port_hint" "Release script must include the current Web reverse proxy engine subscription-port hint."
assert_file_not_contains "src/sni_stack_health.sh" '该端口只给 Caddy 在本机访问' "Subscription hint must not hard-code Caddy as the only local Web reverse proxy engine."
assert_file_not_contains "dist/vps.sh" '该端口只给 Caddy 在本机访问' "Release script must not hard-code Caddy in the subscription-port hint."
subscription_public_hint_calls=$(grep -Ec '^[[:space:]]+print_public_https_reverse_proxy_hint$' src/subscription_apps.sh || true)
if [[ "$subscription_public_hint_calls" -lt 8 ]]; then
    echo "Subscription/Komari installers must show the unified public HTTPS guidance before install and after success." >&2
    exit 1
fi
for stale_hint in \
    '公网 HTTPS 访问建议走 [19] -> [8]' \
    '主菜单 [19] -> [8] 为该本地端口添加 443 反代域名' \
    '公网 HTTPS 可走 Caddy 反代' \
    '未启用 443 单入口可用 [4] -> [1] Caddy 反代' \
    "提示：面板或订阅工具对外访问，""可用 Caddy 反代；已启用 443 单入口时用 [19] 统一管理。" \
    "部署后建议用 Caddy 或 443 单入口""对外访问。"
do
    assert_file_not_contains "src/subscription_apps.sh" "$stale_hint" "Subscription/Komari installers must not use stale public HTTPS guidance: ${stale_hint}"
    assert_file_not_contains "src/menus.sh" "$stale_hint" "Panel/tools menu must not use stale public HTTPS guidance: ${stale_hint}"
    assert_file_not_contains "dist/vps.sh" "$stale_hint" "Release script must not use stale public HTTPS guidance: ${stale_hint}"
done
assert_file_contains "tutorials/03-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md" '主菜单 [4 反代]' "Subscription tutorial must point non-single-entry users at the current reverse proxy menu."
assert_file_contains "tutorials/03-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md" '[2 添加 Nginx HTTPS 反代]' "Subscription tutorial must document the Nginx HTTPS reverse proxy option before 443 single-entry is enabled."
assert_file_contains "tutorials/03-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md" '主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]' "Subscription tutorial must keep the current 443 single-entry Web reverse proxy path."
assert_file_contains "docs/existing-server-migration.md" '未启用 443 单入口时的 HTTPS 反代过渡' "Migration doc must include the non-single-entry HTTPS reverse proxy transition flow."
assert_file_contains "docs/existing-server-migration.md" '[2 添加 Nginx HTTPS 反代]' "Migration doc must document the Nginx HTTPS reverse proxy option before 443 single-entry is enabled."
for file in README.md docs/existing-server-migration.md tutorials/03-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md; do
    assert_file_not_contains "$file" '普通 Caddy 反代' "${file} must not use the old ordinary Caddy reverse proxy wording."
    assert_file_not_contains "$file" '主菜单 [4 普通 Caddy 反代]' "${file} must not point users to the old ordinary Caddy reverse proxy menu."
    assert_file_not_contains "$file" '添加普通 Caddy' "${file} must not use the old add ordinary Caddy wording."
done
assert_file_not_contains 'dist/vps.sh' '普通反代' 'Menu wording should use 反代 without 普通.'
assert_file_not_contains 'dist/vps.sh' '添加普通 Caddy' 'Caddy menu wording should omit 普通.'
assert_file_not_contains 'dist/vps.sh' '添加普通 Nginx' 'Nginx menu wording should omit 普通.'
grep -q '6) func_ssh_security_menu' dist/vps.sh
grep -q '7) func_fail2ban' dist/vps.sh
grep -q '19) func_sni_stack_quick_menu' dist/vps.sh
if grep -q '6) func_add_ssh_key' dist/vps.sh || grep -q '6\..*添加 SSH 公钥' dist/vps.sh || grep -q 'key|pubkey|公钥) echo "6"' dist/vps.sh; then
    echo "Main menu must not keep duplicate SSH public key entry or hidden shortcut compatibility." >&2
    exit 1
fi
if grep -q '18) func_sni_stack_quick_menu' dist/vps.sh; then
    echo "Main menu numbering must be compact after removing duplicate SSH key entry." >&2
    exit 1
fi
grep -q '7) func_hosts_manage' dist/vps.sh
grep -q '8) func_network_interface_manage' dist/vps.sh
grep -Fq "SCRIPT_VERSION=\"${vps_smoke_script_version}\"" dist/vps.sh
grep -q 'SCRIPT_UPDATE_CACHE=' dist/vps.sh
grep -q 'Compatibility marker: VPS 全能控制面板' dist/vps.sh
grep -q 'UPDATE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh"' dist/vps.sh
grep -q '正在尝试自动补齐下载工具' dist/vps.sh
grep -q 'wget -q --timeout=15 --tries=3' dist/vps.sh
grep -q '"${sublink_bind_addr}:${sublink_port}:8000"' dist/vps.sh
grep -q '"${mmw_bind_addr}:${mmw_port}:${mmw_port}"' dist/vps.sh
grep -q 'confirm_risk_action' dist/vps.sh
grep -q 'func_beginner_menu' dist/vps.sh
grep -q 'generate_issue_diagnostics' dist/vps.sh
grep -q 'install_update_script' dog.sh

echo "Smoke tests passed."
