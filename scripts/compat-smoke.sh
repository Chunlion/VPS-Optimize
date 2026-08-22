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

assert_file_not_contains() {
    local file="$1"
    local needle="$2"
    local message="${3:-${file} contains forbidden content: ${needle}}"
    if grep -Fq -- "$needle" "$file"; then
        echo "$message" >&2
        exit 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-${file} must exist.}"
    if [[ ! -f "$file" ]]; then
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

for doc_entry in \
    README.md \
    index.md \
    quick-start.md \
    docs/443-single-entry.md \
    docs/third-party-scripts.md \
    tutorials/01-3x-ui-reality-443.md \
    tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md \
    .vitepress/config.mts \
    .github/workflows/pages.yml; do
    assert_file_exists "$doc_entry"
done

for locale in en ru; do
    for localized_doc in \
        index.md \
        quick-start.md \
        docs/443-single-entry.md \
        docs/443-single-entry-troubleshooting.md \
        docs/443-tcp-peek-engine.md \
        docs/before-use.md \
        docs/config-paths.md \
        docs/dog.md \
        docs/existing-server-migration.md \
        docs/faq.md \
        docs/recovery-runbook.md \
        docs/security-rollback.md \
        docs/subscription-tools.md \
        docs/supported-systems.md \
        docs/third-party-scripts.md \
        docs/update-uninstall.md \
        docs/xui-custom-manager.md \
        tutorials/01-3x-ui-reality-443.md \
        tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md; do
        assert_file_exists "${locale}/${localized_doc}"
    done
done

unexpected_han=$(grep -RInP '[\x{3400}-\x{9fff}]' en ru --include='*.md' | grep -v 'quick-start.md:.*简体中文 (Simplified Chinese)' || true)
if [[ -n "$unexpected_han" ]]; then
    echo "English/Russian docs contain untranslated Chinese text:" >&2
    echo "$unexpected_han" >&2
    exit 1
fi

assert_file_contains README.md 'https://chunlion.github.io/VPS-Optimize/' "README must keep the GitHub Pages docs entry."
assert_file_contains .vitepress/config.mts "base: '/VPS-Optimize/'" "VitePress base must match the GitHub Pages project path."
assert_file_contains .vitepress/config.mts "label: 'English'" "VitePress must expose the English locale."
assert_file_contains .vitepress/config.mts "label: 'Русский'" "VitePress must expose the Russian locale."
assert_file_contains .github/workflows/pages.yml 'run: npm run build' "Pages workflow must build the VitePress site."
assert_file_contains .github/workflows/pages.yml 'path: .vitepress/dist' "Pages workflow must upload the VitePress dist artifact."

assert_file_contains index.md 'layout: home' "Docs homepage must use the VitePress home layout."
assert_file_contains en/index.md 'layout: home' "English docs homepage must use the VitePress home layout."
assert_file_contains ru/index.md 'layout: home' "Russian docs homepage must use the VitePress home layout."
assert_file_not_contains index.md '## 常用文档' "Docs homepage must not render the removed document list."
assert_file_not_contains en/index.md '## Common Documentation' "English docs homepage must not render the removed document list."
assert_file_not_contains ru/index.md '## Основные документы' "Russian docs homepage must not render the removed document list."

assert_file_contains quick-start.md '](docs/443-single-entry.md)' "Quick start must link to the Port 443 Reuse doc."
assert_file_contains quick-start.md '](tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md)' "Quick start must link to the subscription tools 443 tutorial."
assert_file_not_contains quick-start.md '](tutorials/01-3x-ui-reality-443.md)' "Quick start must use the consolidated Port 443 Reuse guide instead of the legacy 3x-ui+Reality page."

assert_file_contains .vitepress/config.mts "link: '/quick-start'" "VitePress nav/sidebar must expose quick start."
assert_file_contains .vitepress/config.mts "link: '/docs/443-single-entry'" "VitePress nav/sidebar must expose the Port 443 Reuse doc."
assert_file_contains .vitepress/config.mts "link: '/docs/third-party-scripts'" "VitePress sidebar must expose third-party script sources."
assert_file_contains .vitepress/config.mts "link: '/tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry'" "VitePress nav/sidebar must expose the subscription tools 443 tutorial."
assert_file_not_contains .vitepress/config.mts "link: '/tutorials/01-3x-ui-reality-443'" "VitePress nav/sidebar must keep the legacy 3x-ui+Reality page hidden after consolidation."

assert_function_once dist/vps.sh main_menu
assert_function_once dist/vps.sh ensure_runtime_root
assert_function_once dist/vps.sh main
assert_function_once dist/vps.sh load_ui_language
assert_function_once dist/vps.sh save_ui_language
assert_function_once dist/vps.sh select_ui_language
assert_function_once dist/vps.sh prompt_initial_ui_language
assert_function_once dist/vps.sh toggle_ui_language
assert_function_once dist/vps.sh func_net_kernel_menu
assert_function_once dist/vps.sh func_kernel_manage
assert_function_once dist/vps.sh configure_ipv4_preference
assert_function_once dist/vps.sh restore_default_ip_preference
assert_function_once dist/vps.sh ipv4_preference_is_enabled
assert_function_once dist/vps.sh func_health_dashboard
assert_function_once dist/vps.sh render_menu
assert_function_once dist/vps.sh dispatch_menu_choice
assert_function_once dist/vps.sh rotate_log_file
assert_function_once dist/vps.sh func_bbr_direct_tune
assert_function_once dist/vps.sh func_server_bandwidth_test
assert_function_once dist/vps.sh func_iperf3_single_thread_test
assert_function_once dist/vps.sh func_international_speed_test
assert_function_once dist/vps.sh func_network_latency_quality_test
assert_function_once dist/vps.sh check_vpso_file_permissions
assert_function_once dist/vps.sh print_vpso_mux_status_json

assert_file_contains src/menus.sh 'NET_KERNEL_MENU_ITEMS=(' "Network/kernel menu must stay on the declarative pilot table."
assert_file_contains src/menus.sh '1|BBR / 拥塞控制管理|调用 ylx2016 多内核调优脚本|func_bbr_manage|net_bbr'
assert_file_contains src/menus.sh '2|动态 TCP 参数调优|粘贴 Omnitt 参数并自动校验|func_tcp_tune|net_tcp_tune'
assert_file_contains src/menus.sh '4|网络接口管理|网卡/路由/DNS/MTU/DHCP|func_network_interface_manage|'
assert_file_contains src/menus.sh '8|BBR 直连/落地优化|检测带宽与 RTT，动态生成 BBR/TCP 参数|func_bbr_direct_tune|net_bbr_direct'
assert_file_contains src/menus.sh '7|内核管理|安装、切换或清理内核|func_kernel_manage|'
assert_file_not_contains src/menus.sh '10|服务器带宽测试|'
assert_file_contains src/diagnostics_network.sh '10. 服务器带宽测试'
assert_file_contains src/diagnostics_network.sh '11. iperf3 单线程测试'
assert_file_contains src/diagnostics_network.sh '12. 国际互联速度测试'
assert_file_contains src/diagnostics_network.sh '13. 网络延迟质量检测'
assert_file_contains src/kernel_tuning.sh '新内核已安装并设为默认启动项，重启后生效。'
assert_file_contains src/kernel_tuning.sh '新内核已安装，但无法确认默认启动项'
assert_file_contains src/kernel_tuning.sh '从主菜单选择 ${RED}[18] 重启服务器'
assert_file_not_contains src/kernel_tuning.sh '选择主菜单的 ${RED}[17] 重启服务器'
assert_file_not_contains src/kernel_tuning.sh '选择 ${GREEN}[5] 清理旧内核'
assert_file_contains src/diagnostics_network.sh '9. TcpQuality TCP 质量测试' "TcpQuality must be exposed in the benchmark menu."
assert_file_contains src/diagnostics_network.sh 'https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh' "TcpQuality must use the requested upstream entry script."
assert_file_contains src/common.sh 'https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh' "TcpQuality must be recognized as a built-in remote script source."
assert_file_contains src/menus.sh '3 面板 SSL 修复：443 接入前清空面板证书路径。' "Panel help item 3 must explain when to clear panel certificate paths."
assert_file_contains dist/vps.sh '3 面板 SSL 修复：443 接入前清空面板证书路径。' "Built panel help item 3 must explain when to clear panel certificate paths."
assert_file_contains src/panel_rescue.sh '面板 SSL 修复${PLAIN}' "Panel SSL repair page title must use the current menu label."
assert_file_contains dist/vps.sh '面板 SSL 修复${PLAIN}' "Built panel SSL repair page title must use the current menu label."
assert_file_not_contains src/panel_rescue.sh '面板紧急救砖 / SSL 清理工具' "Panel SSL repair page title must not keep the old rescue/cleanup label."
assert_file_not_contains dist/vps.sh '面板紧急救砖 / SSL 清理工具' "Built panel SSL repair page title must not keep the old rescue/cleanup label."
assert_file_contains dist/vps.sh '10) func_net_kernel_menu ;;' "Main menu item 10 must still route to network/kernel optimization."
assert_file_contains dist/vps.sh '15) func_health_dashboard ;;' "Main menu item 15 must still route to health dashboard."
assert_file_contains dist/vps.sh '19) func_sni_stack_quick_menu ;;' "Main menu item 19 must still route to Port 443 Reuse center."
assert_file_contains src/menus.sh '443) echo "19"' "The documented 443 shortcut must route to main menu item 19."
assert_file_contains dist/vps.sh 'choice=$(normalize_main_choice "$choice")' "The release main menu must normalize documented shortcuts."
assert_file_not_contains src/menus.sh '443 ·' "Main-menu descriptions must not display shortcut labels."
assert_file_not_contains src/menus.sh 'proxy ·' "Main-menu descriptions must not display shortcut labels."
assert_file_contains README.md '| `443` | `[19 443端口复用管理中心]` |' "The Chinese README must document the 443 shortcut."
assert_file_contains en/README.md '| `443` | `[19 Port 443 Reuse manager]` |' "The English README must document the 443 shortcut."
assert_file_contains ru/README.md '| `443` | `[19 Общий порт 443]` |' "The Russian README must document the 443 shortcut."
assert_file_contains src/menus.sh 'print_menu_item 20 "界面语言"' "Main menu item 20 must expose language selection."
assert_file_contains dist/vps.sh '20) select_ui_language' "Main menu item 20 must open language selection."
assert_file_contains README.md '主菜单 `[20 界面语言]`' "README must document the language menu number."
assert_file_contains quick-start.md '3. Русский (Russian)' "Quick start must document Russian language selection."
assert_file_contains docs/config-paths.md '/etc/vps-optimize/language.conf' "Config paths must document the persisted language setting."

assert_file_contains src/common.sh 'command -v curl' "Remote downloads must keep curl fallback detection."
assert_file_contains src/common.sh 'command -v wget' "Remote downloads must keep wget fallback detection."
assert_file_contains src/common.sh 'install_pkg curl wget' "Remote download helper must still try to install missing download tools."
assert_file_not_contains src/common.sh 'confirm_remote_script_execution' "Remote script execution must not require interactive confirmation."
assert_file_not_contains src/common.sh 'VPSO_REMOTE_SCRIPT_CONFIRM' "Remote script confirmation bypass flag must be removed with the prompt."
assert_file_contains src/common.sh '该来源不是 HTTPS，已拒绝下载和执行' "Remote script execution must reject non-HTTPS sources."
assert_file_contains src/common.sh 'https://raw.githubusercontent.com/MEILOI/VPS_BOT_X/main/vps_bot-x/install.sh' "VPS_BOT_X must be recognized as a built-in remote script source."
assert_file_contains src/panel_installers.sh 'func_vps_bot_x()' "VPS_BOT_X installation function must be defined."
assert_file_contains src/panel_installers.sh 'confirm_danger' "VPS_BOT_X installation must require dangerous-action confirmation."
assert_file_contains src/panel_installers.sh 'https://raw.githubusercontent.com/MEILOI/VPS_BOT_X/main/vps_bot-x/install.sh' "VPS_BOT_X installation must use the requested upstream installer."
assert_file_contains src/menus.sh '14) func_vps_bot_x ;;' "Panel tools menu must expose VPS_BOT_X on option 14."

[[ -f scripts/modules.list ]]
assert_file_contains scripts/build.sh 'scripts/modules.list' "Release build must read the shared module list."
assert_file_contains vps.sh 'scripts/modules.list' "Source checkout entrypoint must read the shared module list."
for module in \
    common language runtime firewall sni_stack_config vpso_mux_state vpso_mux_config \
    vpso_mux_install tcp_peek_engine sni_stack_health compose_runtime \
    subscription_apps subscription_service_menus \
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

assert_file_contains xui-custom-manager.sh 'XUI_SUPPORTED_VERSION_RANGES="${XUI_SUPPORTED_VERSION_RANGES:-2.9.x 3.x}"' "xui-custom-manager must allow 3x-ui 2.9.x and 3.x by default."
assert_file_contains xui-custom-manager.sh '[[ "$detected_version" == 2.9.* ]] && return 0' "xui-custom-manager version gate must allow 2.9.x."
assert_file_contains xui-custom-manager.sh '[[ "$detected_version" == 3.* ]] && return 0' "xui-custom-manager version gate must allow 3.x."
assert_file_contains docs/xui-custom-manager.md '支持使用 SQLite 的 3x-ui 2.9.x 和 3.x。' "xui-custom-manager docs must state the supported SQLite version ranges."
assert_file_not_contains docs/xui-custom-manager.md '只有 3x-ui v2.9.4 验证过写库操作。' "xui-custom-manager docs must not keep the old single-version write gate."
assert_file_contains xui-custom-manager.sh 'require_verified_xui_for_write' "xui-custom-manager must keep a write gate for unsupported 3x-ui versions."
assert_file_contains xui-custom-manager.sh 'require_verified_xui_for_write || return 1' "xui-custom-manager write paths must call the verified-version gate."
assert_file_contains xui-custom-manager.sh 'require_verified_xui_for_write || {' "xui-custom-manager traffic calibration writes must call the verified-version gate."
assert_file_contains xui-custom-manager.sh 'XUI_WRITE_ALLOWED="$xui_write_allowed"' "xui-custom-manager custom reset UI must pass verified write state into the embedded UI."
assert_file_contains xui-custom-manager.sh 'bash -n "$TMP_FILE"' "xcm wrapper must syntax-check downloaded scripts before updating cache."
assert_file_contains xui-custom-manager.sh 'validate_manager_script_source "$self_path"' "install_local_runner must validate the source script before installing."
assert_file_contains xui-custom-manager.sh 'ExecStart=/usr/bin/env bash $LOCAL_RUNNER --reset-check' "xui custom reset service must keep bash-based ExecStart."
assert_file_contains xui-custom-manager.sh 'TimeoutStartSec=900' "xui custom reset service must set TimeoutStartSec."
assert_file_contains xui-custom-manager.sh '--self-test' "xui-custom-manager must expose a non-destructive self-test mode."

assert_file_contains dog.sh '当前统计来自 nftables counter' "dog.sh must explain the nftables counter traffic accounting source."
assert_file_contains dog.sh 'input/output/forward 流量' "dog.sh must explain that monitored-port input/output/forward traffic is counted."
assert_file_contains dog.sh 'show_statistics_health_check' "dog.sh must keep the statistics health check function."
assert_file_contains dog.sh '快照增量' "dog.sh daily reports must explain snapshot-increment accounting."
assert_file_contains dog.sh 'refresh_nftables_counter_snapshot' "dog.sh reports must use one nftables JSON counter snapshot."
assert_file_contains dog.sh '--scheduled-notify' "dog.sh must keep scheduled Telegram notifications."
assert_file_contains dog.sh '{server_name} {report} {time}' "dog.sh must expose the supported Telegram template variables."
assert_file_contains dog.sh '*"(Y/n"*|*"[Y/n]"*|*"直接回车继续"*) input="y" ;;' "dog.sh confirmations must default to yes on empty input."
assert_file_contains xui-custom-manager.sh 'answer="${answer:-yes}"' "xui shell confirmations must default to yes."
assert_file_contains xui-custom-manager.sh '.strip().lower() or "y"' "xui embedded confirmations must default to yes."
assert_file_contains aliyun-cdt-watchdog.sh 'answer=${answer:-yes}' "Aliyun watchdog uninstall confirmation must default to yes."

assert_file_contains docs/443-single-entry.md 'Skip SSL (advanced — behind reverse proxy / SSH tunnel only)' "Port 443 Reuse doc must explain the current 3x-ui Skip SSL flow."
assert_file_contains docs/443-single-entry.md '监听 IP：127.0.0.1' "Port 443 Reuse doc must keep 3x-ui listeners on loopback."
assert_file_contains docs/443-single-entry.md 'REALITY 回落流量防护' "Port 443 Reuse doc must explain REALITY fallback traffic protection."
assert_file_contains en/docs/443-single-entry.md 'REALITY fallback traffic protection' "English Port 443 Reuse doc must explain REALITY fallback traffic protection."
assert_file_contains ru/docs/443-single-entry.md 'Защита трафика REALITY fallback' "Russian Port 443 Reuse doc must explain REALITY fallback traffic protection."
assert_file_contains src/sni_stack_config.sh 'xui_database_backend()' "443 helpers must detect the configured 3x-ui database backend."
assert_file_contains src/sni_stack_config.sh 'xui_uses_postgresql && return 1' "443 helpers must not query PostgreSQL through sqlite3."
assert_file_contains src/sni_stack_profiles.sh 'xui_uses_postgresql' "443 profile updates must skip PostgreSQL database synchronization."
assert_file_not_contains docs/443-single-entry.md '监听 IP：首次安装阶段可以先留空或用默认' "Port 443 Reuse doc must not tell users to leave the panel listen IP blank first."
assert_file_not_contains docs/443-single-entry.md '监听 IP：先留空或用默认，443 跑通后再改 127.0.0.1' "Port 443 Reuse doc must not defer subscription loopback binding until after 443 works."
assert_file_not_contains docs/443-single-entry.md '首次临时登录通常是：' "Port 443 Reuse doc must not recommend temporary direct public panel access."
assert_file_not_contains docs/443-single-entry.md '清空后，如果还需要临时从公网端口访问面板' "Port 443 Reuse doc must not keep the old direct-public-port fallback."

assert_file_contains dist/vps.sh '/var/lib/vps-optimize/vpso-mux/status.json'
assert_file_contains dist/vps.sh 'ExecCondition=/bin/grep -Fxq "ENTRY_MODE='"'"'tcp-peek'"'"'" /etc/vps-optimize/sni-stack.env' "vpso-mux must not start outside TCP Peek mode."
assert_file_contains dist/vps.sh '/var/log/vps-traffic-guard.log'
assert_file_contains dist/vps.sh 'traffic_guard_install_checker_once'
assert_file_contains dist/vps.sh 'traffic_guard_install_checker_or_report'
assert_file_contains dist/vps.sh 'backend_retry_attempts'
assert_file_contains dist/vps.sh "STRICT_SNI_GATE='\${strict_sni_gate}'" "Release script must persist the strict SNI gate setting."
assert_file_contains dist/vps.sh 'limitFallbackUpload' "Release script must include the limited REALITY fallback patcher."
assert_file_contains dist/vps.sh '17) manage_reality_traffic_guard' "Port 443 Reuse menu must expose REALITY fallback traffic protection."
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
    rm -f "$compat_tmp_dir/language.conf"
    rmdir "$compat_tmp_dir" 2>/dev/null || true
}
trap cleanup_compat_tmp EXIT

source src/common.sh
VPSO_LANGUAGE_CONFIG="$compat_tmp_dir/language.conf"
source src/language.sh
source src/ui.sh
source src/input.sh
source src/validate.sh
source src/kernel_tuning.sh
source src/system_core.sh

for function_name in terminal_text_width print_menu_item render_menu dispatch_menu_choice rotate_log_file format_bytes load_ui_language save_ui_language localized_text select_ui_language prompt_initial_ui_language toggle_ui_language; do
    assert_function_loaded "$function_name"
done

[[ "$(localized_text "中文" "English")" == "中文" ]]
save_ui_language en
[[ "$VPSO_LANGUAGE" == "en" ]]
[[ "$(localized_text "中文" "English")" == "English" ]]
[[ "$(cat "$VPSO_LANGUAGE_CONFIG")" == "LANGUAGE=en" ]]
VPSO_LANGUAGE="zh"
load_ui_language
[[ "$VPSO_LANGUAGE" == "en" ]]
select_ui_language initial <<<"3" >/dev/null
[[ "$VPSO_LANGUAGE" == "ru" ]]
[[ "$(localized_text "中文" "English" "Русский")" == "Русский" ]]
[[ "$(cat "$VPSO_LANGUAGE_CONFIG")" == "LANGUAGE=ru" ]]

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
gai_test_file="$compat_tmp_dir/gai.conf"
printf '%s\n' '#precedence ::ffff:0:0/96  10' 'precedence ::ffff:0:0/96  50' 'precedence ::ffff:0:0/96  100' > "$gai_test_file"
configure_ipv4_preference "$gai_test_file"
ipv4_preference_is_enabled "$gai_test_file"
[[ "$(grep -Ec '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100$' "$gai_test_file")" == "1" ]]
assert_file_contains "$gai_test_file" '#precedence ::ffff:0:0/96  10'
assert_file_not_contains "$gai_test_file" 'precedence ::ffff:0:0/96  50'
configure_ipv4_preference "$gai_test_file"
[[ "$(grep -Ec '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100$' "$gai_test_file")" == "1" ]]
restore_default_ip_preference "$gai_test_file"
assert_file_not_contains "$gai_test_file" 'precedence ::ffff:0:0/96  100'
[[ "$(find "$compat_tmp_dir" -maxdepth 1 -type f -name 'gai.conf.bak_*' | wc -l)" == "2" ]]
[[ "$(bbr_direct_buffer_mb 100 near)" == "8" ]]
[[ "$(bbr_direct_buffer_mb 1000 near)" == "16" ]]
[[ "$(bbr_direct_buffer_mb 1000 long)" == "64" ]]
[[ "$(extract_speedtest_upload_mbps 'Upload: 123.45 Mbit/s')" == "123" ]]
[[ "$(extract_speedtest_upload_mbps 'Upload: 1.25 Gbit/s')" == "1250" ]]
[[ "$(extract_speedtest_download_mbps 'Download: 850.6 Mbps')" == "851" ]]
[[ "$(extract_speedtest_latency_ms 'Latency: 12.6 ms (0.8 ms jitter)')" == "13" ]]
[[ "$(bbr_direct_buffer_mb_for_rtt 100 80)" == "8" ]]
[[ "$(bbr_direct_buffer_mb_for_rtt 1000 80)" == "20" ]]
[[ "$(bbr_direct_buffer_mb_for_rtt 1000 250)" == "60" ]]
[[ "$(bbr_direct_buffer_mb_for_rtt 10000 300)" == "64" ]]
[[ "$(bbr_direct_queue_values 100 80)" == "131072|2048|4096|5000|16384" ]]
[[ "$(bbr_direct_queue_values 2000 200)" == "524288|8192|16384|20000|65536" ]]
bbr_candidate="$compat_tmp_dir/bbr-direct.conf"
write_bbr_direct_candidate "$bbr_candidate" 2000 200 64
assert_file_contains "$bbr_candidate" 'net.core.rmem_default = 524288'
assert_file_contains "$bbr_candidate" 'net.ipv4.tcp_moderate_rcvbuf = 1'
assert_file_contains "$bbr_candidate" 'net.core.somaxconn = 8192'
assert_file_contains "$bbr_candidate" 'net.core.netdev_max_backlog = 20000'
assert_file_contains "$bbr_candidate" 'net.ipv4.tcp_notsent_lowat = 65536'
if bbr_direct_buffer_mb_for_rtt 100001 80 >/dev/null 2>&1; then
    echo "BBR buffer sizing must reject unreasonable bandwidth values." >&2
    exit 1
fi
bbr_verify="$compat_tmp_dir/bbr-verify.conf"
printf 'net.test.values = 1 2 3\n' > "$bbr_verify"
sysctl() {
    [[ "$1" == "-n" && "$2" == "net.test.values" ]] || return 1
    printf '1\t2  3\n'
}
sysctl_tune_verify_file "$bbr_verify"
unset -f sysctl
read_trimmed() {
    printf -v "$1" '%s' "${MOCK_TRIMMED_VALUE:-}"
}
ensure_speedtest_client() { return 0; }
run_speedtest_client() {
    printf '%s\n' 'Latency: 20.4 ms' 'Download: 900.2 Mbps' 'Upload: 1.25 Gbit/s'
}
MOCK_TRIMMED_VALUE=1
[[ "$(prompt_bbr_measurement 2>/dev/null)" == "1250|20|900" ]]
MOCK_TRIMMED_VALUE=4
[[ "$(prompt_bbr_rtt_ms 20 2>/dev/null)" == "20" ]]
unset MOCK_TRIMMED_VALUE

echo "Compatibility smoke passed."
