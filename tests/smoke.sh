#!/usr/bin/env bash
set -euo pipefail

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
build_order=$(awk '/^[[:space:]]+[a-z0-9_]+\.sh/{print $1}' scripts/build.sh | tr '\n' ' ')
case "$build_order" in
    *"sni_stack_config.sh vpso_mux_state.sh vpso_mux_config.sh vpso_mux_install.sh tcp_peek_engine.sh sni_stack_health.sh"*) ;;
    *)
        echo "vpso-mux/TCP Peek modules are not in the expected build order." >&2
        exit 1
        ;;
esac
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
[[ "$(normalize_domain_input " HTTPS://Panel.Example.COM:443/path ")" == "panel.example.com" ]]
declare -f func_edit_applied_config_center >/dev/null
declare -f edit_applied_config_file >/dev/null
declare -f validate_applied_config_kind >/dev/null
declare -f collect_applied_config_files >/dev/null
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
    rm -f "$nginx_proxy_tmp"
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

    rm -f "$(single_443_engine_state_path)"
    rmdir "$entry_mode_tmp_dir"
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
    "tutorials/03-subscription-tools-with-caddy.md"
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
if grep -Fq 'raw.githubusercontent.com/alireza0/s-ui/master/install.sh' dist/vps.sh; then
    echo "S-UI installer URL must not be present in the release script." >&2
    exit 1
fi
if grep -Fq 'S-UI' dist/vps.sh; then
    echo "S-UI menu text must not be present in the release script." >&2
    exit 1
fi
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
grep -q 'func_edit_applied_proxy_config' dist/vps.sh
grep -q '6) func_edit_applied_proxy_config ;;' dist/vps.sh
grep -q 'collect_editable_proxy_config_files' dist/vps.sh
grep -q 'validate_proxy_config_kind' dist/vps.sh
grep -q 'reload_proxy_config_kind' dist/vps.sh
grep -q 'nginx_proxy_warn_if_single_entry_enabled' dist/vps.sh
grep -q 'write_nginx_reverse_proxy_conf' dist/vps.sh
grep -q '/etc/nginx/conf.d/vps_proxy_${domain}.conf' dist/vps.sh
grep -q '/etc/nginx/conf.d/00-vps-proxy-map.conf' dist/vps.sh
grep -q 'issue_and_install_cert_for_domain "$domain" "$CF_TOKEN"' dist/vps.sh
grep -q 'systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx' dist/vps.sh
grep -q '4. 查看/编辑 Compose 配置' dist/vps.sh
grep -q 'edit_applied_config_file "$compose_file" "compose"' dist/vps.sh
assert_file_contains "README.md" '主菜单 [16 配置备份与回滚] -> [5 查看/编辑脚本已应用配置]' "README must document the global applied-config editor."
assert_file_contains "docs/config-paths.md" '主菜单 [16 配置备份与回滚] -> [5 查看/编辑脚本已应用配置]' "Config paths doc must list the global applied-config editor."
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
