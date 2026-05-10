#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bash scripts/build.sh >/dev/null

bash -n scripts/build.sh
bash -n vps.sh
bash -n dist/vps.sh
bash -n src/common.sh
bash -n src/ui.sh
bash -n src/input.sh
bash -n src/validate.sh
bash -n src/rollback.sh
bash -n src/backup.sh
bash -n src/main.sh
bash -n dog.sh
bash -n xui-custom-manager.sh
grep -q 'modules=(' scripts/build.sh
grep -q 'main.sh     # feature implementation and menu wiring' scripts/build.sh

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
APT_UPDATED=1
apt_update_once
[[ "$APT_UPDATED" == "1" ]]
[[ "$(nginx_stream_listen_directives "127.0.0.1" "443")" == "    listen 127.0.0.1:443;" ]]
[[ "$(nginx_stream_listen_directives "0.0.0.0" "443" | grep -c '^    listen ')" == "2" ]]
[[ "$(nginx_stream_listen_directives "::1" "443")" == "    listen [::1]:443;" ]]
[[ "$(xui_cert_setting_key_sql_list)" == *"subcertfile"* ]]

(
    source <(sed -n '/^configure_system_timezone_for_init()/,/^# --- 启动面板 ---/p' src/main.sh | sed '$d')
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
grep -q 'switch_public_443_to_tcp_peek' dist/vps.sh
grep -q 'rollback_tcp_peek_to_nginx_stream' dist/vps.sh
grep -q 'sni_stack_health_check_enhanced' dist/vps.sh
grep -q 'vpso-mux.service' dist/vps.sh
grep -q 'vpso-mux-preflight.service' dist/vps.sh
grep -q 'go_install_vpso_mux_latest' dist/vps.sh
grep -q 'GOTOOLCHAIN=local' dist/vps.sh
grep -q '拒绝在生产机上自动下载临时 Go 工具链' dist/vps.sh
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
19|切换公网 443 到 TCP Peek + Splice 模式|switch_public_443_to_tcp_peek ;;
20|从 TCP Peek 回滚到 Nginx Stream 模式|rollback_tcp_peek_to_nginx_stream ;;
SNI_MENU_MAP
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
