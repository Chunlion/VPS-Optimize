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
grep -q 'traffic|quota|bill|流量|达量|账单) echo "9"' dist/vps.sh
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
grep -q '5) func_ssh_security_menu' dist/vps.sh
grep -q '6) func_fail2ban' dist/vps.sh
grep -q '18) func_sni_stack_quick_menu' dist/vps.sh
if grep -q '6) func_add_ssh_key' dist/vps.sh || grep -q '6\..*添加 SSH 公钥' dist/vps.sh || grep -q 'key|pubkey|公钥) echo "6"' dist/vps.sh; then
    echo "Main menu must not keep duplicate SSH public key entry or hidden shortcut compatibility." >&2
    exit 1
fi
if grep -q '19) func_sni_stack_quick_menu' dist/vps.sh; then
    echo "Main menu numbering must be compact after removing duplicate SSH key entry." >&2
    exit 1
fi
grep -q '7) func_hosts_manage' dist/vps.sh
grep -q '8) func_network_interface_manage' dist/vps.sh
grep -q 'SCRIPT_VERSION="v1.8"' dist/vps.sh
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
