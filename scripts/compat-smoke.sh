#!/usr/bin/env bash
set -euo pipefail
trap 'echo "compat-smoke failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

assert_file_contains() {
    local file="$1"
    local needle="$2"
    local message="${3:-${file} is missing required content: ${needle}}"
    if ! grep -Fq -- "$needle" "$file"; then
        echo "$message" >&2
        exit 1
    fi
}

assert_function_once() {
    local file="$1"
    local function_name="$2"
    local count
    count=$(grep -Ec "^${function_name}\\(\\) \\{" "$file" || true)
    if [[ "$count" != "1" ]]; then
        echo "${function_name} must be defined exactly once in ${file}; found ${count}." >&2
        exit 1
    fi
}

bash scripts/build.sh >/dev/null
bash -n scripts/build.sh scripts/selfcheck.sh scripts/compat-smoke.sh
bash -n vps.sh dist/vps.sh dog.sh xui-custom-manager.sh
for module in src/*.sh; do
    bash -n "$module"
done

assert_function_once dist/vps.sh main_menu
assert_function_once dist/vps.sh func_net_kernel_menu
assert_function_once dist/vps.sh func_health_dashboard
assert_function_once dist/vps.sh render_menu
assert_function_once dist/vps.sh dispatch_menu_choice
assert_function_once dist/vps.sh rotate_log_file
assert_function_once dist/vps.sh check_vpso_file_permissions
assert_function_once dist/vps.sh print_vpso_mux_status_json

assert_file_contains src/menus.sh 'NET_KERNEL_MENU_ITEMS=(' "Network/kernel menu must stay on the declarative pilot table."
assert_file_contains src/menus.sh '1|BBR / 拥塞控制管理|调用 ylx2016 多内核调优脚本|func_bbr_manage|net_bbr'
assert_file_contains src/menus.sh '2|动态 TCP 参数调优|粘贴 Omnitt 参数并自动校验|func_tcp_tune|net_tcp_tune'
assert_file_contains src/menus.sh '8|网卡管理工具|网卡/路由/DNS/MTU/DHCP|func_network_interface_manage|'
assert_file_contains dist/vps.sh '10) func_net_kernel_menu ;;' "Main menu item 10 must still route to network/kernel optimization."
assert_file_contains dist/vps.sh '15) func_health_dashboard ;;' "Main menu item 15 must still route to health dashboard."
assert_file_contains dist/vps.sh '19) func_sni_stack_quick_menu ;;' "Main menu item 19 must still route to 443 single-entry center."

assert_file_contains src/common.sh 'command -v curl' "Remote downloads must keep curl fallback detection."
assert_file_contains src/common.sh 'command -v wget' "Remote downloads must keep wget fallback detection."
assert_file_contains src/common.sh 'install_pkg curl wget' "Remote download helper must still try to install missing download tools."
assert_file_contains src/common.sh 'confirm_risk_action "$desc"' "Remote script execution must use the unified risk prompt when available."

assert_file_contains dist/vps.sh '/var/lib/vps-optimize/vpso-mux/status.json'
assert_file_contains dist/vps.sh '/var/log/vps-traffic-guard.log'
assert_file_contains dist/vps.sh 'backend_retry_attempts'
assert_file_contains dist/vps.sh '日志容量摘要'
assert_file_contains dist/vps.sh '配置与状态文件权限体检'

echo "Compatibility smoke passed."
