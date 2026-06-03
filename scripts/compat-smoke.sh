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

module_list_entries() {
    awk '
        {
            sub(/#.*/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 != "") print
        }
    ' scripts/modules.list
}

assert_module_list_contains() {
    local module="$1"
    if ! module_list_entries | grep -Fxq "$module"; then
        echo "scripts/modules.list is missing required module: ${module}" >&2
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

assert_function_loaded() {
    local function_name="$1"
    if ! declare -F "$function_name" >/dev/null 2>&1; then
        echo "${function_name} must be loadable during compatibility smoke." >&2
        exit 1
    fi
}

bash scripts/build.sh >/dev/null
bash -n scripts/build.sh scripts/selfcheck.sh scripts/compat-smoke.sh scripts/validate-traffic-guard-checker.sh
bash scripts/validate-traffic-guard-checker.sh
bash -n vps.sh dist/vps.sh dog.sh xui-custom-manager.sh
for module in src/*.sh; do
    bash -n "$module"
done

assert_function_once dist/vps.sh main_menu
assert_function_once dist/vps.sh ensure_runtime_root
assert_function_once dist/vps.sh main
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

[[ -f scripts/modules.list ]]
assert_file_contains scripts/build.sh 'scripts/modules.list' "Release build must read the shared module list."
assert_file_contains vps.sh 'scripts/modules.list' "Source checkout entrypoint must read the shared module list."
for module in \
    common runtime firewall sni_stack_config vpso_mux_state vpso_mux_config \
    vpso_mux_install tcp_peek_engine sni_stack_health compose_runtime \
    subscription_apps subscription_compose_manage subscription_service_menus \
    dockge_migration menus main; do
    assert_module_list_contains "$module"
    assert_file_contains dist/vps.sh "# Module: ${module}.sh" "Release script is missing key module: ${module}.sh"
done

assert_file_contains scripts/build.sh 'validate-traffic-guard-checker.sh' "Release build must validate embedded Traffic Guard checker templates before writing checksums."
assert_file_contains src/traffic_guard.sh 'ExecStart=/usr/bin/env bash ${TRAFFIC_GUARD_CHECKER}' "Traffic Guard systemd service must keep bash-based ExecStart."
assert_file_contains src/traffic_guard.sh 'bash -n "$tmp_checker"' "Traffic Guard checker install must validate Bash syntax before replacing the live checker."
assert_file_contains src/traffic_guard.sh "grep -q \$'\\r' \"\$tmp_checker\"" "Traffic Guard checker install must reject CRLF before replacing the live checker."
assert_file_contains src/traffic_guard.sh 'mv -f "$tmp_checker" "$TRAFFIC_GUARD_CHECKER"' "Traffic Guard checker install must atomically replace the live checker after validation."
assert_file_contains src/traffic_guard.sh '/usr/bin/env bash "$TRAFFIC_GUARD_CHECKER"' "Traffic Guard direct fallback must invoke checker through bash."
assert_file_contains src/traffic_guard.sh 'traffic_guard_install_checker_once' "Traffic Guard checker install must keep a single-attempt helper for safe retry handling."
assert_file_contains src/traffic_guard.sh 'generated-content' "Traffic Guard checker install must classify generated-content validation failures."
assert_file_contains src/traffic_guard.sh 'retry checker install once after generated content validation failure' "Traffic Guard checker install must retry generated-content validation failures once."
assert_file_contains src/traffic_guard.sh 'traffic_guard_install_checker_or_report' "Traffic Guard first configuration failure path must print direct diagnostics."

assert_file_contains dist/vps.sh '/var/lib/vps-optimize/vpso-mux/status.json'
assert_file_contains dist/vps.sh '/var/log/vps-traffic-guard.log'
assert_file_contains dist/vps.sh 'traffic_guard_install_checker_once'
assert_file_contains dist/vps.sh 'traffic_guard_install_checker_or_report'
assert_file_contains dist/vps.sh 'backend_retry_attempts'
assert_file_contains dist/vps.sh '日志容量摘要'
assert_file_contains dist/vps.sh '配置与状态文件权限体检'

compat_tmp_dir=$(mktemp -d /tmp/vps-compat-smoke.XXXXXX)
cleanup_compat_tmp() {
    [[ -n "${compat_tmp_dir:-}" && -d "$compat_tmp_dir" ]] || return 0
    rm -f "$compat_tmp_dir/missing.log"
    rm -f "$compat_tmp_dir/missing.log.1"
    rm -f "$compat_tmp_dir/empty.log"
    rm -f "$compat_tmp_dir/empty.log.1"
    rm -f "$compat_tmp_dir/small.log"
    rm -f "$compat_tmp_dir/small.log.1"
    rm -f "$compat_tmp_dir/large.log"
    rm -f "$compat_tmp_dir/large.log.1"
    rm -f "$compat_tmp_dir/large.log.2"
    rm -f "$compat_tmp_dir/large.log.3"
    rmdir "$compat_tmp_dir" 2>/dev/null || true
}
trap cleanup_compat_tmp EXIT

source src/common.sh
source src/ui.sh

for function_name in render_menu dispatch_menu_choice rotate_log_file format_bytes; do
    assert_function_loaded "$function_name"
done

compat_menu_handler_called=0
compat_menu_handler() {
    compat_menu_handler_called=1
}
COMPAT_MENU_ITEMS=(
    "1|Compat check|No-op handler|compat_menu_handler|"
)
render_output=$(render_menu COMPAT_MENU_ITEMS)
[[ "$render_output" == *"Compat check"* ]]
if dispatch_menu_choice "invalid" COMPAT_MENU_ITEMS; then
    echo "dispatch_menu_choice must reject invalid input without dispatching." >&2
    exit 1
fi
[[ "$compat_menu_handler_called" == "0" ]]

rotate_log_file "$compat_tmp_dir/missing.log" 1 3
touch "$compat_tmp_dir/empty.log"
rotate_log_file "$compat_tmp_dir/empty.log" 1 3
[[ -f "$compat_tmp_dir/empty.log" ]]
[[ ! -e "$compat_tmp_dir/empty.log.1" ]]

printf 'abc' > "$compat_tmp_dir/small.log"
rotate_log_file "$compat_tmp_dir/small.log" 10 3
[[ -f "$compat_tmp_dir/small.log" ]]
[[ ! -e "$compat_tmp_dir/small.log.1" ]]

printf 'abcdef' > "$compat_tmp_dir/large.log"
rotate_log_file "$compat_tmp_dir/large.log" 4 3
[[ ! -e "$compat_tmp_dir/large.log" ]]
[[ -f "$compat_tmp_dir/large.log.1" ]]

[[ -n "$(format_bytes 0)" ]]
[[ -n "$(format_bytes 1024)" ]]
[[ -n "$(format_bytes 1048576)" ]]

echo "Compatibility smoke passed."
