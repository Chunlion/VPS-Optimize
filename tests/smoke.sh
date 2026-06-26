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

assert_function_body_contains() {
    local file="$1"
    local function_name="$2"
    local needle="$3"
    local message="${4:-${function_name} in ${file} must contain: ${needle}}"
    if ! awk -v fn="$function_name" -v needle="$needle" '
        $0 ~ "^" fn "\\(\\) \\{" { in_fn = 1 }
        in_fn && index($0, needle) { found = 1 }
        in_fn && $0 == "}" { exit }
        END { exit found ? 0 : 1 }
    ' "$file"; then
        echo "$message" >&2
        exit 1
    fi
}

function_body_from_file() {
    local file="$1"
    local function_name="$2"
    awk -v fn="$function_name" '
        $0 ~ "^" fn "\\(\\) \\{" { in_fn = 1 }
        in_fn { print }
        in_fn && $0 == "}" { exit }
    ' "$file"
}

assert_shadow_function_matches_release_owner() {
    local shadow_file="$1"
    local owner_file="$2"
    local function_name="$3"
    local shadow_body owner_body
    shadow_body=$(function_body_from_file "$shadow_file" "$function_name")
    owner_body=$(function_body_from_file "$owner_file" "$function_name")
    if [[ -z "$shadow_body" || -z "$owner_body" ]]; then
        echo "${function_name} must exist in both ${shadow_file} and release owner ${owner_file}." >&2
        exit 1
    fi
    if [[ "$shadow_body" != "$owner_body" ]]; then
        echo "${function_name} in ${shadow_file} must match release owner ${owner_file}; edit the built module first." >&2
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

bash -n scripts/build.sh
bash -n scripts/selfcheck.sh
bash -n scripts/compat-smoke.sh
bash -n vps.sh
bash -n dist/vps.sh
for module in src/*.sh; do
    bash -n "$module"
done
bash -n dog.sh
bash -n xui-custom-manager.sh
[[ -f scripts/modules.list ]]
for module in \
    common runtime firewall sni_stack_config vpso_mux_state vpso_mux_config \
    vpso_mux_install tcp_peek_engine sni_stack_health compose_runtime \
    subscription_apps subscription_compose_manage subscription_service_menus \
    dockge_migration menus main; do
    assert_module_list_contains "$module"
    assert_dist_contains "# Module: ${module}.sh" "Release script is missing key module: ${module}.sh"
done
assert_file_contains scripts/build.sh 'scripts/modules.list' "Release build must read the shared module list."
assert_file_contains scripts/build.sh "sed '1{/^#!\\/usr\\/bin\\/env bash$/d;}'" "Release build must only strip module-level shebangs, not embedded script templates."
assert_file_contains .github/workflows/shell-syntax.yml 'bash scripts/selfcheck.sh' "CI must call the shared selfcheck entrypoint."
assert_file_contains .github/workflows/shell-syntax.yml 'bash scripts/compat-smoke.sh' "CI must call the compatibility smoke entrypoint."
assert_file_contains .github/workflows/shell-syntax.yml 'windows-selfcheck-wrapper' "CI must include a lightweight Windows selfcheck.ps1 wrapper validation job."
assert_file_contains .github/workflows/shell-syntax.yml 'runs-on: windows-latest' "Windows wrapper validation must run on a Windows runner."
assert_file_contains .github/workflows/shell-syntax.yml './scripts/selfcheck-ps1-contract.ps1' "Windows wrapper validation must run the focused selfcheck.ps1 contract test."
assert_file_contains scripts/selfcheck-ps1-contract.ps1 '[System.Management.Automation.Language.Parser]::ParseFile' "PowerShell contract test must parse scripts/selfcheck.ps1."
assert_file_contains scripts/selfcheck-ps1-contract.ps1 'VPSO_WSL_EXE' "PowerShell contract test must mock WSL instead of running the real Linux selfcheck."
assert_file_contains scripts/selfcheck-ps1-contract.ps1 "cd '/mnt/c/Users/O'\\''Brian/VPS-Optimize'" "PowerShell contract test must verify Bash path quoting."
assert_file_contains scripts/selfcheck-ps1-contract.ps1 'exit code 37' "PowerShell contract test must verify WSL bash exit-code passthrough."
assert_file_contains scripts/selfcheck-ps1-contract.ps1 'exit 0' "PowerShell contract test must explicitly return success after mocked failure checks."
assert_file_contains scripts/selfcheck.sh 'tests/smoke.sh' "Bash selfcheck must syntax-check the full smoke gate."
assert_file_contains scripts/selfcheck.sh 'bash tests/golden-render.sh' "Bash selfcheck must run golden render validation."
assert_file_contains scripts/selfcheck.sh 'bash scripts/compat-smoke.sh' "Bash selfcheck must run compatibility smoke validation."
assert_file_contains scripts/selfcheck.sh 'bash tests/smoke.sh' "Bash selfcheck must run full smoke validation."
assert_file_contains scripts/selfcheck.ps1 'wsl.exe' "PowerShell selfcheck wrapper must execute validation through WSL."
assert_file_contains scripts/selfcheck.ps1 'VPSO_WSL_EXE' "PowerShell selfcheck wrapper must support a mockable WSL command for CI contract tests."
assert_file_contains scripts/selfcheck.ps1 'bash scripts/selfcheck.sh' "PowerShell selfcheck wrapper must delegate to the Bash selfcheck through WSL."
assert_file_contains scripts/selfcheck.ps1 'exit $exitCode' "PowerShell selfcheck wrapper must pass through the failing WSL exit code."
assert_file_contains vps.sh 'scripts/modules.list' "Source checkout entrypoint must read the shared module list."
assert_dist_contains 'ensure_runtime_root()' "Release script must include the runtime root guard function."
assert_dist_contains 'main()' "Release script must include the bootstrap main function."
assert_function_defined_once dist/vps.sh ensure_runtime_root
assert_function_defined_once dist/vps.sh main
assert_function_body_contains dist/vps.sh main 'ensure_runtime_root' "main must check root before entering the menu."
assert_function_body_contains dist/vps.sh main 'main_menu' "main must enter the top-level menu."
assert_dist_contains 'rotate_log_file' "Release script must include the shared log rotation helper."
assert_dist_contains 'print_log_capacity_summary' "Health overview must include log capacity summary."
assert_dist_contains 'check_vpso_file_permissions' "Health overview must expose file permission checks."
assert_dist_contains '7. Forwardx 转发面板' "Basic components menu must include Forwardx."
assert_dist_contains 'https://raw.githubusercontent.com/poouo/Forwardx/main/scripts/install-panel-local.sh' "Release script must include the Forwardx local panel installer."
assert_file_not_contains dist/vps.sh '10. 宝塔面板' "Basic components menu must not keep the old Baota option label."
assert_dist_contains 'NET_KERNEL_MENU_ITEMS=(' "Network/kernel menu must use the declarative pilot table."
assert_dist_contains 'dispatch_menu_choice "$nk_choice" NET_KERNEL_MENU_ITEMS' "Network/kernel menu must dispatch through the menu helper pilot."
assert_dist_contains 'backend_retry_attempts' "vpso-mux status must expose backend retry attempts."
assert_dist_contains 'backend_retry:' "vpso-mux generated config must include explicit default retry settings."
assert_dist_contains 'max_size_bytes: 5242880' "vpso-mux generated config must include default file-log rotation size."
assert_file_contains internal/mux/config.go 'BackendRetry struct' "vpso-mux config must include optional backend retry defaults."
assert_file_contains cmd/vpso-mux/main_linux_test.go 'TestDialBackendWithRetrySuccess' "vpso-mux backend retry behavior must have tests."
assert_dist_contains '# Module: firewall.sh' "Release script must include src/firewall.sh."
assert_dist_contains 'func_port_connlimit_menu' "Release script is missing the port connlimit menu."
assert_dist_contains 'VPSO_CONN_LIMIT_PORT_' "Release script is missing the connlimit rule marker."
assert_dist_contains 'func_save_port_connlimit_persistence' "Release script is missing the connlimit persistence save action."
assert_dist_contains 'auto_save_port_connlimit_persistence_after_change "添加规则"' "Adding connlimit rules must trigger automatic persistence refresh."
assert_dist_contains 'auto_save_port_connlimit_persistence_after_change "删除规则"' "Deleting connlimit rules must trigger automatic persistence refresh."
assert_dist_contains 'netfilter-persistent save' "Release script must use the existing netfilter-persistent save path for connlimit persistence."
assert_dist_contains '/etc/iptables/rules.v4' "Release script must verify the IPv4 persistent rules file."
assert_dist_contains '/etc/sysconfig/iptables' "Release script must support the existing RHEL iptables-services persistence file."
assert_dist_contains 'iptables-save' "Release script must support RHEL iptables-save persistence when iptables-services is present."
assert_dist_contains '当前 connlimit 规则只在本次运行期生效' "Release script must clearly warn when connlimit persistence is unavailable."
assert_dist_contains 'print_port_connlimit_health_summary' "Health overview must include the connlimit persistence summary."
assert_dist_contains 'connlimit 持久化摘要' "Health overview must expose connlimit persistence status."
assert_dist_contains '运行时/保存文件' "Health overview must show runtime/persistent connlimit consistency."
assert_dist_contains '重启风险提示' "Health overview must show connlimit reboot risk hints."
assert_dist_contains 'print_443_health_connlimit_scope_notice' "443 health check must include connlimit scope diagnostics."
assert_dist_contains 'print_443_single_entry_issue_summary' "Issue diagnostics must include a compact 443 single-entry summary."
assert_dist_contains 'print_443_issue_connlimit_summary' "Issue diagnostics must include compact public 443 connlimit diagnostics."
assert_file_contains src/sni_stack_health.sh '影响范围：该限制只能作用于整个公网 443 入口，不能精准到某个 SNI、Xray/3x-ui 入站、UUID 或用户。' "443 health check must explain connlimit scope precisely."
assert_file_contains src/preflight.sh '443 单入口摘要:' "Issue diagnostics must label the compact 443 single-entry summary."
assert_file_contains src/preflight.sh '443 connlimit: 检测到本脚本添加的公网 443 connlimit 规则' "Issue diagnostics must warn when script-owned public 443 connlimit rules exist."
assert_dist_contains '影响范围：该限制只能作用于整个公网 443 入口，不能精准到某个 SNI、Xray/3x-ui 入站、UUID 或用户。' "Release script must include the 443 connlimit scope warning."
assert_file_contains src/menus.sh '如果存在脚本添加的 connlimit 规则，也会显示持久化后端、运行时/保存文件一致性和重启风险提示。' "Health help must mention the connlimit persistence summary."
assert_file_contains docs/config-paths.md '主菜单 [3 基础组件与常用服务] -> [7 Forwardx 转发面板]' "Config paths doc must document the current Forwardx menu path."
assert_file_contains docs/config-paths.md '主菜单 [3 基础组件与常用服务] -> [10 nftables NAT 转发]' "Config paths doc must document the current nftables NAT menu path."
assert_file_contains docs/443-single-entry-troubleshooting.md '端口并发连接限制误伤' "443 troubleshooting doc must include connlimit false-positive guidance."
assert_file_contains docs/443-single-entry-troubleshooting.md '如果公网 `443` 存在本脚本添加的 connlimit 规则，它只能作用于整个公网 `443`，不能精准到某个 SNI、Xray/3x-ui 入站、UUID 或用户。' "443 troubleshooting doc must explain public 443 connlimit scope."
assert_file_contains docs/443-single-entry-troubleshooting.md '主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]' "443 troubleshooting doc must point users to the 443 health check."
assert_file_contains docs/443-single-entry-troubleshooting.md '主菜单 [8 防火墙规则管理] -> [6 端口并发连接限制]' "443 troubleshooting doc must point users to the connlimit menu."
assert_file_contains docs/recovery-runbook.md '端口并发连接限制误封' "Recovery runbook must include connlimit lockout guidance."
assert_file_contains docs/recovery-runbook.md '不要批量清空 INPUT 链' "Recovery runbook must warn against broad firewall cleanup for connlimit recovery."
assert_function_defined_once dist/vps.sh func_firewall_manage
module_order=$(module_list_entries | tr '\n' ' ')
case "$module_order" in
    *"sni_stack_config vpso_mux_state vpso_mux_config vpso_mux_install tcp_peek_engine sni_stack_health"*) ;;
    *)
        echo "vpso-mux/TCP Peek modules are not in the expected build order." >&2
        exit 1
        ;;
esac
case "$module_order" in
    *"panel_installers compose_runtime subscription_apps subscription_compose_manage subscription_service_menus dockge_migration panel_rescue"*) ;;
    *)
        echo "Compose management modules are not in the expected build order." >&2
        exit 1
        ;;
esac
if module_list_entries | grep -Fxq 'subscription_tools'; then
    echo "Release build must use the split compose/subscription modules directly." >&2
    exit 1
fi
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
    ensure_docker_engine_ready \
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
assert_module_list_contains sni_stack_sites
assert_dist_contains '# Module: sni_stack_sites.sh' "Release script must include the active 443 Web/SNI site module."
assert_path_absent "src/sni_stack_web_sites.sh" "sni_stack_web_sites.sh is a stale shadow implementation; use src/sni_stack_sites.sh."
if module_list_entries | grep -Fxq 'sni_stack_web_sites'; then
    echo "Stale sni_stack_web_sites.sh must not be added to the release build." >&2
    exit 1
fi
assert_file_not_contains dist/vps.sh '# Module: sni_stack_web_sites.sh' "Release script must not include the stale sni_stack_web_sites module."
assert_path_absent "src/entry_mode_cutover.sh" "entry_mode_cutover.sh is a stale shadow implementation; use src/tcp_peek_engine.sh."
assert_path_absent "src/tcp_peek_preflight.sh" "tcp_peek_preflight.sh is a stale shadow implementation; use src/tcp_peek_engine.sh."
if module_list_entries | grep -Fxq 'entry_mode_state'; then
    echo "entry_mode_state.sh is a non-release shadow; entry-mode fixes must land in src/sni_stack_config.sh." >&2
    exit 1
fi
if module_list_entries | grep -Fxq 'entry_mode_cutover'; then
    echo "Stale entry-mode cutover module must not be added to the release build." >&2
    exit 1
fi
if module_list_entries | grep -Fxq 'tcp_peek_preflight'; then
    echo "Stale TCP Peek preflight module must not be added to the release build." >&2
    exit 1
fi
assert_file_not_contains dist/vps.sh '# Module: entry_mode_state.sh' "Release script must not include non-release entry_mode_state.sh."
expected_entry_mode_shadow_functions=$(cat <<'ENTRY_MODE_SHADOW_FUNCTIONS'
canonical_legacy_entry_mode_name
entry_mode_expected_listener
get_entry_mode
print_entry_mode_compat_notice
rewrite_legacy_entry_mode_assignment
set_entry_mode
sni_stack_env_path
ENTRY_MODE_SHADOW_FUNCTIONS
)
actual_entry_mode_shadow_functions=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*\(\) \{' src/entry_mode_state.sh \
    | sed 's/().*//' \
    | grep -E '(^get_entry_mode$|entry_mode|legacy|sni_stack_env_path|compat|rewrite|canonical)' \
    | sort)
if ! diff -u <(printf '%s\n' "$expected_entry_mode_shadow_functions" | sort) <(printf '%s\n' "$actual_entry_mode_shadow_functions") >/dev/null; then
    echo "src/entry_mode_state.sh contains unexpected release-owned entry-mode helpers; edit src/sni_stack_config.sh instead." >&2
    diff -u <(printf '%s\n' "$expected_entry_mode_shadow_functions" | sort) <(printf '%s\n' "$actual_entry_mode_shadow_functions") >&2 || true
    exit 1
fi
while IFS= read -r function_name; do
    [[ -n "$function_name" ]] || continue
    assert_shadow_function_matches_release_owner "src/entry_mode_state.sh" "src/sni_stack_config.sh" "$function_name"
    assert_dist_contains "${function_name}()" "Release script must include entry-mode helper ${function_name} from built modules."
done <<< "$expected_entry_mode_shadow_functions"
assert_file_contains src/README.md '443/TCP Peek ownership:' "Source README must document 443/TCP Peek module ownership."
assert_file_contains src/README.md 'Do not reintroduce split shadow modules' "Source README must warn against stale split 443/TCP Peek modules."
assert_function_body_contains src/sni_stack_menus.sh manage_sni_stack_sites 'read_trimmed choice "👉 请输入菜单编号或 ?: "' "443 Web/SNI submenu must prompt for a menu number or help."
assert_function_body_contains src/sni_stack_profiles.sh edit_sni_stack_runtime_profile 'read_trimmed choice "👉 请输入菜单编号或 ?: "' "443 shared-parameter submenu must prompt for a menu number or help."
assert_function_body_contains src/menus.sh func_sni_stack_quick_menu 'read_trimmed sni_choice "👉 请输入菜单编号或 ?: "' "443 single-entry menu must prompt for a menu number or help."
assert_function_body_contains src/sni_stack_menus.sh manage_sni_stack_sites '"?"|help) show_sni_help; pause_return; continue ;;' "443 Web/SNI submenu must accept ? help."
assert_function_body_contains src/sni_stack_profiles.sh edit_sni_stack_runtime_profile '"?"|help) show_sni_help; pause_return; continue ;;' "443 shared-parameter submenu must accept ? help."
assert_function_body_contains src/menus.sh func_sni_stack_quick_menu '"?"|help) show_sni_help; pause_return; continue ;;' "443 single-entry menu must accept ? help."
assert_function_body_contains src/sni_stack_menus.sh manage_sni_stack_sites '0) break ;;' "443 Web/SNI submenu must rely on normalized back words."
assert_function_body_contains src/sni_stack_profiles.sh edit_sni_stack_runtime_profile '0) break ;;' "443 shared-parameter submenu must rely on normalized back words."
assert_function_body_contains src/menus.sh func_sni_stack_quick_menu '0) break ;;' "443 single-entry menu must rely on normalized back words."
assert_function_body_contains src/sni_stack_menus.sh manage_sni_stack_sites 'q/back/返回' "443 Web/SNI submenu must advertise common back words."
assert_function_body_contains src/sni_stack_profiles.sh edit_sni_stack_runtime_profile 'q/back/返回' "443 shared-parameter submenu must advertise common back words."
assert_function_body_contains src/menus.sh func_sni_stack_quick_menu 'q/back/返回' "443 single-entry menu must advertise common back words."
assert_dist_contains '请输入菜单编号或 ?' "Release script must include hardened 443 menu prompts."
assert_dist_contains '❌ 无效选择，请输入菜单编号或 ?。' "Release script must include hardened 443 invalid-choice guidance."
if command -v go >/dev/null 2>&1; then
    GO_BIN=go
elif command -v go.exe >/dev/null 2>&1; then
    GO_BIN=go.exe
elif [[ "${VPSO_CI_CONTAINER:-0}" == "1" ]]; then
    GO_BIN=""
else
    echo "Go is required for vpso-mux release validation." >&2
    exit 1
fi
if [[ -n "${GO_BIN:-}" ]]; then
    GOTOOLCHAIN=local "$GO_BIN" test ./...
else
    echo "Go not found; skipped Go smoke validation in VPSO_CI_CONTAINER mode."
fi

dangerous_patterns='rm -rf|rm -r[[:space:]]|wget .*[&][&]|curl .*\|[[:space:]]*gpg|\|[[:space:]]*bash|bash[[:space:]]*<'
if grep -En "$dangerous_patterns" dist/vps.sh dog.sh; then
    echo "Dangerous shell patterns found." >&2
    exit 1
fi

source src/common.sh
vps_smoke_script_version="$SCRIPT_VERSION"
(
    OS=unknown
    OS_LIKE=unknown
    if install_pkg somepkg >/tmp/vps-smoke-install-unknown.out 2>&1; then
        echo "install_pkg must fail on unknown OS." >&2
        exit 1
    fi
    grep -Fq '当前系统暂不支持自动安装软件包' /tmp/vps-smoke-install-unknown.out
    rm -f /tmp/vps-smoke-install-unknown.out

    if remove_pkg somepkg >/tmp/vps-smoke-remove-unknown.out 2>&1; then
        echo "remove_pkg must fail on unknown OS." >&2
        exit 1
    fi
    grep -Fq '当前系统暂不支持自动卸载软件包' /tmp/vps-smoke-remove-unknown.out
    rm -f /tmp/vps-smoke-remove-unknown.out
)
source src/ui.sh
source src/input.sh
source src/validate.sh
source src/rollback.sh
source src/backup.sh

assert_ip_cidr_valid() {
    local value="$1"
    if ! is_valid_ip_cidr "$value"; then
        echo "Expected valid IP/CIDR: ${value}" >&2
        exit 1
    fi
}

assert_ip_cidr_invalid() {
    local value="$1"
    if is_valid_ip_cidr "$value"; then
        echo "Expected invalid IP/CIDR: ${value}" >&2
        exit 1
    fi
}

for cidr_value in 1.2.3.4 1.2.3.0/24 2001:db8::1 2001:db8::/32 ::1; do
    assert_ip_cidr_valid "$cidr_value"
done
for cidr_value in 999.1.1.1 1.2.3.4/33 2001:::1 2001:db8::1::2 2001:db8::/129 zzzz::1; do
    assert_ip_cidr_invalid "$cidr_value"
done
(
    command() {
        if [[ "$1" == "-v" && "${2:-}" == "python3" ]]; then
            return 1
        fi
        builtin command "$@"
    }
    assert_ip_cidr_valid 2001:db8::1
    assert_ip_cidr_valid 2001:db8::/32
    assert_ip_cidr_invalid 2001:::1
    assert_ip_cidr_invalid 2001:db8::1::2
    assert_ip_cidr_invalid 2001:db8::/129
    assert_ip_cidr_invalid zzzz::1
)
declare -a ip_whitelist_smoke=()
normalize_ip_whitelist_input '２００１:DB8::１，2001:db8::/32、[2001:DB8::2]/128;::1 ２００１:db8::１' ip_whitelist_smoke
[[ "${#ip_whitelist_smoke[@]}" -eq 4 ]]
[[ "${ip_whitelist_smoke[0]}" == "2001:db8::1" ]]
[[ "${ip_whitelist_smoke[2]}" == "2001:db8::2/128" ]]
if normalize_ip_whitelist_input '2001:::1' ip_whitelist_smoke >/dev/null 2>&1; then
    echo "normalize_ip_whitelist_input must reject invalid IPv6 input." >&2
    exit 1
fi

declare -a split_smoke=()
split_csv_to_array $'Site1.Example.com site2.example.com，site3.example.com、site4.example.com;site5.example.com\nsite6.example.com' split_smoke
[[ "${#split_smoke[@]}" -eq 6 ]]
[[ "${split_smoke[0]}" == "site1.example.com" ]]
[[ "${split_smoke[5]}" == "site6.example.com" ]]

[[ "$(trim_input "  q  ")" == "q" ]]
[[ "$(normalize_menu_choice_input "  q  ")" == "0" ]]
[[ "$(normalize_menu_choice_input " 返回 ")" == "0" ]]
[[ "$(normalize_menu_choice_input " １ ")" == "1" ]]
[[ "$(normalize_menu_choice_input "１０、")" == "10" ]]
[[ "$(normalize_menu_choice_input "2)")" == "2" ]]
[[ "$(LC_ALL=C normalize_menu_choice_input "１０、")" == "10" ]]
[[ "$(LC_ALL=C normalize_menu_choice_input "３．")" == "3" ]]
choice=""
read_trimmed choice "" <<< " 返回 "
[[ "$choice" == "0" ]]
choice=""
read_trimmed choice "" <<< " Q "
[[ "$choice" == "0" ]]
action=""
read_trimmed action "" <<< "back"
[[ "$action" == "0" ]]
c=""
read_trimmed c "" <<< "３．"
[[ "$c" == "3" ]]
t=""
read_trimmed t "" <<< "退出"
[[ "$t" == "0" ]]
mode_choice=""
read_trimmed mode_choice "" <<< "back"
[[ "$mode_choice" == "back" ]]
action_choice=""
read_trimmed action_choice "" <<< "返回"
[[ "$action_choice" == "返回" ]]
port=""
read_trimmed port "" <<< "https://panel.example.com:４００００/path"
[[ "$port" == "40000" ]]
p_choice=""
read_trimmed p_choice "" <<< "４４３）"
[[ "$p_choice" == "443" ]]
final_p=""
read_trimmed final_p "" <<< "１００２２"
[[ "$final_p" == "10022" ]]
ip=""
read_trimmed ip "" <<< "https://[2001:DB8::1]:443/path"
[[ "$ip" == "2001:db8::1" ]]
ip_whitelist_input=""
read_trimmed ip_whitelist_input "" <<< "1.1.1.1 2.2.2.2/32"
[[ "$ip_whitelist_input" == "1.1.1.1 2.2.2.2/32" ]]
[[ "$(ask_with_default "后端端口" "3000" <<< "https://site.example.com:８４４３/path")" == "8443" ]]
[[ "$(ask_with_default "本地监听地址" "127.0.0.1" <<< "https://[::1]:443/path")" == "::1" ]]
[[ "$(ask_with_default "普通订阅路径前缀（不带端口）" "/sub/" <<< "/sub/")" == "/sub/" ]]
is_yes "yes"
is_yes "YES"
is_yes "YeS"
if is_yes "no"; then
    echo "is_yes must not accept no." >&2
    exit 1
fi
[[ "$(normalize_domain_input " HTTPS://Panel.Example.COM:443/path ")" == "panel.example.com" ]]
[[ "$(normalize_domain_input " HTTPS：//Panel。Example。COM:４４３/path?x=1#frag ")" == "panel.example.com" ]]
[[ "$(normalize_domain_input "panel.example.com.")" == "panel.example.com" ]]
[[ "$(normalize_ip_input "１．２．３．４:443")" == "1.2.3.4" ]]
[[ "$(normalize_ip_input "https://[2001:DB8::1]:443/path")" == "2001:db8::1" ]]
[[ "$(normalize_port_input "https://panel.example.com:４４３/path")" == "443" ]]
is_valid_port "https://panel.example.com:４４３/path"
[[ "$(normalize_port_rule_input "８０，４４３；1000：1002、2000-2001")" == "80,443,1000-1002,2000-2001" ]]
[[ "$(dns_normalize_servers 4 "１．１．１．１，8.8.8.8 9.9.9.9")" == "1.1.1.1 8.8.8.8 9.9.9.9" ]]
[[ "$(dns_normalize_servers 6 "[2001:4860:4860::8888]、2001:4860:4860::8844")" == "2001:4860:4860::8888 2001:4860:4860::8844" ]]
(
    source src/system_core.sh
    declare -a host_names_smoke=()
    hosts_normalize_names 'Panel。Example。COM、node.example.com;vps01 panel.example.com' host_names_smoke
    [[ "${#host_names_smoke[@]}" -eq 3 ]]
    [[ "${host_names_smoke[0]}" == "panel.example.com" ]]
    [[ "${host_names_smoke[2]}" == "vps01" ]]
)
(
    source src/system_hosts.sh
    declare -a host_names_smoke=()
    hosts_normalize_names 'Panel。Example。COM、node.example.com;vps01 panel.example.com' host_names_smoke
    [[ "${#host_names_smoke[@]}" -eq 3 ]]
    [[ "${host_names_smoke[0]}" == "panel.example.com" ]]
    [[ "${host_names_smoke[2]}" == "vps01" ]]
)
bad_domain_raw="https：//例子。测试/path"
bad_domain_normalized=$(normalize_domain_input "$bad_domain_raw")
if is_valid_domain "$bad_domain_normalized"; then
    echo "Non-ASCII pasted domain must remain invalid." >&2
    exit 1
fi
bad_domain_output=$(print_domain_validation_error "测试域名" "$bad_domain_raw" "$bad_domain_normalized")
[[ "$bad_domain_output" == *"测试域名格式无效"* ]]
[[ "$bad_domain_output" == *"中文/全角标点"* ]]
[[ "$bad_domain_output" == *"类似 URL"* ]]
[[ "$bad_domain_output" == *"脚本规范化后用于校验的值"* ]]
(
    source src/kernel_tuning.sh
    mapfile -t tcp_tune_records < <(
        while IFS= read -r tcp_tune_candidate; do
            tcp_tune_record=$(sysctl_tune_normalize_record "$tcp_tune_candidate")
            tcp_tune_status=$?
            case "$tcp_tune_status" in
                0) printf '%s\n' "$tcp_tune_record" ;;
                1) ;;
                *) exit 2 ;;
            esac
        done < <(sysctl_tune_split_line 'net.ipv4.tcp_fin_timeout = 15 net.ipv4.tcp_rmem = 4096 87380 67108864; sysctl -w net.core.default_qdisc=fq')
    )
    [[ "${#tcp_tune_records[@]}" -eq 3 ]]
    [[ "${tcp_tune_records[0]}" == "net.ipv4.tcp_fin_timeout = 15" ]]
    [[ "${tcp_tune_records[1]}" == "net.ipv4.tcp_rmem = 4096 87380 67108864" ]]
    [[ "${tcp_tune_records[2]}" == "net.core.default_qdisc = fq" ]]
    tcp_tune_bad_status=0
    sysctl_tune_normalize_record 'net.ipv4.tcp_fin_timeout 15' >/dev/null || tcp_tune_bad_status=$?
    [[ "$tcp_tune_bad_status" == "2" ]]
)
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
(
    compose_apply_tmp=$(mktemp -d /tmp/vps-compose-apply-smoke.XXXXXX)
    mkdir -p "$compose_apply_tmp/src" "$compose_apply_tmp/project"
    printf '%s\n' 'services: {}' > "$compose_apply_tmp/project/docker-compose.yml"
    cat > "$compose_apply_tmp/src/compose_runtime.sh" <<'SMOKE_COMPOSE_RUNTIME'
ensure_docker_compose_ready() {
    DOCKER_COMPOSE_CMD=mock_compose_cmd
    printf loaded > "$COMPOSE_HELPER_MARKER"
}
SMOKE_COMPOSE_RUNTIME
    mock_compose_cmd() {
        printf '%s\n' "$*" > "$COMPOSE_CMD_ARGS"
        [[ "$1" == "-f" && "$2" == "$compose_apply_tmp/project/docker-compose.yml" && "$3" == "up" && "$4" == "-d" ]]
    }
    unset -f ensure_docker_compose_ready install_docker_compose_standalone ensure_docker_engine_ready 2>/dev/null || true
    SCRIPT_DIR="$compose_apply_tmp" \
        COMPOSE_HELPER_MARKER="$compose_apply_tmp/helper.marker" \
        COMPOSE_CMD_ARGS="$compose_apply_tmp/compose.args" \
        reload_applied_config_kind compose "$compose_apply_tmp/project/docker-compose.yml" <<< "y"
    grep -Fq loaded "$compose_apply_tmp/helper.marker"
    grep -Fq -- "-f $compose_apply_tmp/project/docker-compose.yml up -d" "$compose_apply_tmp/compose.args"
    rm -f "$compose_apply_tmp/src/compose_runtime.sh"
    rm -f "$compose_apply_tmp/project/docker-compose.yml"
    rm -f "$compose_apply_tmp/helper.marker"
    rm -f "$compose_apply_tmp/compose.args"
    rmdir "$compose_apply_tmp/src"
    rmdir "$compose_apply_tmp/project"
    rmdir "$compose_apply_tmp"
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
assert_file_contains src/common.sh 'sudo bash coreutils findutils grep sed gawk util-linux git nano htop lsof net-tools' "Minimal compatibility packages must include basic system commands."
assert_file_contains src/system_core.sh 'install_pkg sudo curl wget git nano unzip htop lsof net-tools' "Base init must install sudo and common tools."
assert_file_contains src/preflight.sh 'command -v sudo >/dev/null 2>&1 || cmd_miss+=("sudo")' "Preflight must detect missing sudo as a basic command."

(
    source src/common.sh
    source src/firewall.sh

    OS=rocky
    OS_LIKE="rhel fedora"
    SMOKE_HAVE_NETFILTER=0
    SMOKE_HAVE_IPV4_SAVE=1
    SMOKE_HAVE_IPV6_SAVE=1
    SMOKE_RUNTIME_V4=0
    SMOKE_RUNTIME_V6=0
    SMOKE_SAVED_V4=0
    SMOKE_SAVED_V6=0

    dpkg-query() { return 1; }
    systemctl() {
        case "$1" in
            is-enabled) printf '%s\n' "enabled" ;;
            is-active) printf '%s\n' "active" ;;
            *) return 0 ;;
        esac
    }
    port_connlimit_command_path() {
        case "$1" in
            netfilter-persistent) [[ "$SMOKE_HAVE_NETFILTER" == "1" ]] && printf '%s\n' "/mock/sbin/netfilter-persistent" ;;
            iptables-save) [[ "$SMOKE_HAVE_IPV4_SAVE" == "1" ]] && printf '%s\n' "/mock/sbin/iptables-save" ;;
            ip6tables-save) [[ "$SMOKE_HAVE_IPV6_SAVE" == "1" ]] && printf '%s\n' "/mock/sbin/ip6tables-save" ;;
            iptables) printf '%s\n' "/mock/sbin/iptables" ;;
            ip6tables) printf '%s\n' "/mock/sbin/ip6tables" ;;
            *) return 1 ;;
        esac
    }
    port_connlimit_systemd_unit_exists() {
        [[ "$1" == "iptables" || "$1" == "ip6tables" ]]
    }
    port_connlimit_runtime_rule_count() {
        case "$1" in
            iptables) printf '%s' "$SMOKE_RUNTIME_V4" ;;
            ip6tables) printf '%s' "$SMOKE_RUNTIME_V6" ;;
            *) printf '0' ;;
        esac
    }
    port_connlimit_persisted_rule_count() {
        case "$1" in
            /etc/sysconfig/iptables) printf '%s' "$SMOKE_SAVED_V4" ;;
            /etc/sysconfig/ip6tables) printf '%s' "$SMOKE_SAVED_V6" ;;
            *) printf '0' ;;
        esac
    }

    [[ "$(port_connlimit_persistence_backend)" == "rhel-iptables-services" ]]
    [[ "$(port_connlimit_saved_file_for_family 4)" == "/etc/sysconfig/iptables" ]]
    [[ "$(port_connlimit_saved_file_for_family 6)" == "/etc/sysconfig/ip6tables" ]]

    SMOKE_HAVE_IPV4_SAVE=0
    [[ "$(port_connlimit_persistence_backend)" == "none" ]]
    SMOKE_HAVE_IPV4_SAVE=1

    connlimit_save_capture=$(mktemp /tmp/vps-rhel-connlimit-save-smoke.XXXXXX)
    save_rhel_port_connlimit_family() {
        printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$connlimit_save_capture"
        return 0
    }
    enable_port_connlimit_persistence_service() { :; }
    save_rhel_port_connlimit_persistence >/dev/null
    grep -Fq '/mock/sbin/iptables-save|/etc/sysconfig/iptables|IPv4' "$connlimit_save_capture"
    grep -Fq '/mock/sbin/ip6tables-save|/etc/sysconfig/ip6tables|IPv6' "$connlimit_save_capture"
    rm -f "$connlimit_save_capture"

    SMOKE_RUNTIME_V4=1
    SMOKE_RUNTIME_V6=0
    SMOKE_SAVED_V4=0
    SMOKE_SAVED_V6=0
    connlimit_status_output=$(print_port_connlimit_persistence_status 2>&1)
    grep -Fq '已检测到 RHEL 系列已有 iptables-services 持久化路径' <<<"$connlimit_status_output"
    grep -Fq '检测到运行时 connlimit 规则尚未出现在当前可用的保存文件中' <<<"$connlimit_status_output"

    SMOKE_RUNTIME_V4=0
    SMOKE_RUNTIME_V6=0
    SMOKE_SAVED_V4=1
    SMOKE_SAVED_V6=0
    connlimit_status_output=$(print_port_connlimit_persistence_status 2>&1)
    grep -Fq '运行时没有脚本规则，但保存文件里仍有旧标记' <<<"$connlimit_status_output"

    port_connlimit_runtime_rule_fingerprints() {
        printf '%s\n' 'IPv4:-A INPUT -p tcp --dport 443 -m comment --comment VPSO_CONN_LIMIT_PORT_443 -j REJECT'
    }
    port_connlimit_saved_rule_fingerprints_for_backend() {
        printf '%s\n' 'IPv4:-A INPUT -p tcp --dport 8443 -m comment --comment VPSO_CONN_LIMIT_PORT_8443 -j REJECT'
    }
    port_connlimit_known_saved_rule_fingerprints() {
        port_connlimit_saved_rule_fingerprints_for_backend "$1"
    }
    connlimit_health_output=$(print_port_connlimit_health_summary 2>&1)
    grep -Fq '运行时/保存文件' <<<"$connlimit_health_output"
    grep -Fq '不一致' <<<"$connlimit_health_output"
    grep -Fq '运行时规则与保存文件不同' <<<"$connlimit_health_output"
)

(
    source src/common.sh
    source src/ui.sh
    source src/input.sh
    source src/validate.sh
    source src/diagnostics_status.sh
    source src/firewall.sh
    source src/sni_stack_config.sh
    source src/preflight.sh

    load_sni_stack_env() {
        ENTRY_MODE=tcp-peek
        WEB_PROXY_ENGINE=nginx
        NGINX_LISTEN_PORT=443
        CADDY_LISTEN_ADDR=127.0.0.1
        CADDY_LISTEN_PORT=8443
        XRAY_LISTEN_ADDR=127.0.0.1
        XRAY_LISTEN_PORT=1443
        PANEL_DOMAIN=panel.example.com
        PANEL_WEB_PATH=/panel/
        PANEL_LISTEN_ADDR=127.0.0.1
        PANEL_LISTEN_PORT=40000
        SUB_URI_PATH=/sub/
        CLASH_URI_PATH=/clash/
        SUB_LISTEN_ADDR=127.0.0.1
        SUB_LISTEN_PORT=2096
        SITE_DOMAINS=(site.example.com)
        TCP_ROUTE_SNIS=(tcp.example.com)
        XRAY_SNI_ROUTE_SNIS=(node.example.com)
        return 0
    }
    detect_current_entry_status() {
        ENTRY_STATUS_MODE="$ENTRY_MODE"
        ENTRY_STATUS_LISTENER_DISPLAY="TCP Peek + Splice 模式 (vpso-mux 分流器)"
        ENTRY_STATUS_LISTENER_PROCESS="tcppeek"
        ENTRY_STATUS_CONSISTENT="yes"
    }
    port_connlimit_runtime_rule_fingerprints() {
        printf '%s\n' 'IPv4:-A INPUT -p tcp --dport 443 -m comment --comment VPSO_CONN_LIMIT_PORT_443 -j REJECT'
    }
    port_connlimit_known_saved_rule_fingerprints() {
        printf '%s\n' 'IPv4:-A INPUT -p tcp --dport 443 -m comment --comment VPSO_CONN_LIMIT_PORT_443 -j REJECT'
    }

    issue_443_output=$(print_443_single_entry_issue_summary 2>&1)
    grep -Fq 'ENTRY_MODE: tcp-peek' <<<"$issue_443_output"
    grep -Fq '公网 443 监听归属: TCP Peek + Splice 模式 (vpso-mux 分流器) (tcppeek); 与 ENTRY_MODE 一致' <<<"$issue_443_output"
    grep -Fq 'Caddy/Web 本地后端: Nginx 本地 HTTPS 反代 127.0.0.1:8443' <<<"$issue_443_output"
    grep -Fq 'Xray 本地后端: 127.0.0.1:1443' <<<"$issue_443_output"
    grep -Fq '面板路径: https://panel.example.com/panel/ -> 127.0.0.1:40000' <<<"$issue_443_output"
    grep -Fq '订阅路径: 普通 /sub/, Clash/Mihomo /clash/ -> 127.0.0.1:2096' <<<"$issue_443_output"
    grep -Fq '扩展路由: Web 1 个, TCP/SNI 1 个, Xray 入站 1 个' <<<"$issue_443_output"
    grep -Fq '443 connlimit: 检测到本脚本添加的公网 443 connlimit 规则 (VPSO_CONN_LIMIT_PORT_443)' <<<"$issue_443_output"
    grep -Fq '不能精确到某个 SNI' <<<"$issue_443_output"
)

[[ "$(nginx_stream_listen_directives "127.0.0.1" "443")" == "    listen 127.0.0.1:443;" ]]
[[ "$(nginx_stream_listen_directives "0.0.0.0" "443" | grep -c '^    listen ')" == "2" ]]
[[ "$(nginx_stream_listen_directives "::1" "443")" == "    listen [::1]:443;" ]]
[[ "$(xui_cert_setting_key_sql_list)" == *"subcertfile"* ]]
assert_function_body_contains src/sni_stack_profiles.sh edit_sni_stack_panel_domain_profile 'update_xui_panel_domain_settings_for_single_443 "$old_domain" "$new_domain"' "Panel domain changes must sync 3x-ui domain settings."

if command -v python3 >/dev/null 2>&1; then
    (
        source src/common.sh
        source src/sni_stack_profiles.sh
        xui_domain_smoke_tmp=$(mktemp -d /tmp/vps-xui-domain-smoke.XXXXXX)
        command mkdir -p "$xui_domain_smoke_tmp/bin" "$xui_domain_smoke_tmp/backups"
        xui_domain_db="$xui_domain_smoke_tmp/x-ui.db"
        cat > "$xui_domain_smoke_tmp/bin/sqlite3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
db_path="$1"
shift
sql="$1"
python3 - "$db_path" "$sql" <<'PY'
import os
import re
import shutil
import sqlite3
import sys

db_path = sys.argv[1]
sql = sys.argv[2]
if sql.startswith(".backup"):
    match = re.search(r"\.backup\s+'([^']+)'", sql)
    if not match:
        sys.exit(1)
    backup_path = match.group(1)
    backup_root = os.environ.get("SMOKE_XUI_BACKUP_ROOT")
    if backup_root and backup_path.startswith("/root/x-ui-backups/"):
        backup_path = os.path.join(backup_root, os.path.basename(backup_path))
    os.makedirs(os.path.dirname(backup_path), exist_ok=True)
    shutil.copyfile(db_path, backup_path)
    sys.exit(0)

conn = sqlite3.connect(db_path)
try:
    if sql.lstrip().lower().startswith("select name from sqlite_master"):
        row = conn.execute(sql).fetchone()
        if row and row[0] is not None:
            print(row[0])
    else:
        conn.executescript(sql)
        conn.commit()
finally:
    conn.close()
PY
EOF
        chmod +x "$xui_domain_smoke_tmp/bin/sqlite3"
        python3 - "$xui_domain_db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("create table settings (key text primary key, value text)")
rows = [
    ("webDomain", "old.panel.example.com"),
    ("subDomain", "old.panel.example.com"),
    ("subURI", "https://old.panel.example.com/old-sub/"),
    ("subClashURI", "https://old.panel.example.com/old-clash/"),
    ("subJsonURI", "http://old.panel.example.com/json/sub?token=1"),
    ("otherSetting", "https://old.panel.example.com/unchanged"),
]
conn.executemany("insert into settings values (?, ?)", rows)
conn.commit()
conn.close()
PY
        find_xui_database_candidates() {
            printf '%s\n' "$xui_domain_db"
        }
        restart_xui_panel_services_after_setting_update() {
            xui_domain_smoke_restarted=1
        }
        mkdir() {
            if [[ "$#" -eq 2 && "$1" == "-p" && "$2" == "/root/x-ui-backups" ]]; then
                command mkdir -p "$xui_domain_smoke_tmp/backups"
                return 0
            fi
            command mkdir "$@"
        }
        SUB_URI_PATH=/sub/
        CLASH_URI_PATH=/clash/
        xui_domain_smoke_restarted=0
        PATH="$xui_domain_smoke_tmp/bin:$PATH" \
        SMOKE_XUI_BACKUP_ROOT="$xui_domain_smoke_tmp/backups" \
            update_xui_panel_domain_settings_for_single_443 old.panel.example.com new.panel.example.com >/dev/null
        xui_domain_values=$(python3 - "$xui_domain_db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
for key, value in conn.execute("select key, value from settings order by key"):
    print(f"{key}={value}")
conn.close()
PY
)
        grep -Fxq 'webDomain=' <<<"$xui_domain_values"
        grep -Fxq 'subDomain=new.panel.example.com' <<<"$xui_domain_values"
        grep -Fxq 'subURI=https://new.panel.example.com/sub/' <<<"$xui_domain_values"
        grep -Fxq 'subClashURI=https://new.panel.example.com/clash/' <<<"$xui_domain_values"
        grep -Fxq 'subJsonURI=https://new.panel.example.com/json/sub?token=1' <<<"$xui_domain_values"
        grep -Fxq 'otherSetting=https://old.panel.example.com/unchanged' <<<"$xui_domain_values"
        [[ "$xui_domain_smoke_restarted" == "1" ]]
        xui_domain_backup=$(find "$xui_domain_smoke_tmp/backups" -type f -name 'x-ui.db.panel_domain_*.bak' | head -n1)
        [[ -n "$xui_domain_backup" && -f "$xui_domain_backup" ]]
        rm -f "$xui_domain_backup"
        rm -f "$xui_domain_smoke_tmp/bin/sqlite3"
        rm -f "$xui_domain_db"
        rmdir "$xui_domain_smoke_tmp/backups"
        rmdir "$xui_domain_smoke_tmp/bin"
        rmdir "$xui_domain_smoke_tmp"
    )
fi

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
    sni_stack_env_path() { printf '%s\n' "$entry_mode_tmp_dir/sni-stack.env"; }

    [[ "$(normalize_entry_mode_name "nginx_stream")" == "nginx-stream" ]]
    [[ "$(normalize_entry_mode_name "xray_fallback")" == "xray-fallback" ]]
    [[ "$(normalize_entry_mode_name "tcp_peek")" == "tcp-peek" ]]
    [[ "$(entry_mode_engine_name "tcp_peek")" == "tcp-peek" ]]

    printf '%s\n' "ENTRY_MODE='tcp_peek'" > "$(sni_stack_env_path)"
    [[ "$(get_entry_mode)" == "tcp-peek" ]]
    grep -Fq "ENTRY_MODE='tcp-peek'" "$(sni_stack_env_path)"
    [[ "$(single_443_current_engine)" == "tcp-peek" ]]

    printf '%s\n' "ENTRY_MODE='nginx_stream'" "ENTRY_MODE='tcp_peek'" > "$(sni_stack_env_path)"
    [[ "$(get_entry_mode)" == "tcp-peek" ]]
    grep -Fq "ENTRY_MODE='nginx_stream'" "$(sni_stack_env_path)"
    printf '%s\n' "ENTRY_MODE='tcp-peek'" > "$(sni_stack_env_path)"

    printf '%s\n' "engine='tcp_peek'" > "$(single_443_engine_state_path)"
    [[ "$(single_443_current_engine)" == "tcp-peek" ]]
    grep -Fq "engine='tcp-peek'" "$(single_443_engine_state_path)"
    printf '%s\n' "engine='nginx_stream'" > "$(single_443_engine_state_path)"
    [[ "$(single_443_current_engine)" == "nginx-stream" ]]
    grep -Fq "engine='nginx-stream'" "$(single_443_engine_state_path)"
    printf '%s\n' "engine='xray-fallback'" > "$(single_443_engine_state_path)"
    [[ "$(single_443_current_engine)" == "xray-fallback" ]]

    initial_entry_output="$entry_mode_tmp_dir/initial-entry.out"
    select_initial_entry_mode >"$initial_entry_output" 2>&1 <<< $'3\nYeS\n'
    [[ "$ENTRY_MODE" == "nginx-stream" ]]
    grep -Fq 'TCP Peek 首次接管 443 前必须先安装/使用 Nginx Stream' "$initial_entry_output"
    grep -Fq '已选择 443 入口模式：nginx-stream' "$initial_entry_output"

    rm -f "$(single_443_engine_state_path)"
    rm -f "$(sni_stack_env_path)"
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
[[ "$(is_trusted_remote_script_url "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh")" == *"VPS-Optimize"* ]]
[[ "$(is_trusted_remote_script_url "https://raw.githubusercontent.com/zywe03/realm-xwPF/main/xwPF.sh")" == *"项目内置硬编码外部脚本源"* ]]
[[ "$(is_trusted_remote_script_url "https://raw.githubusercontent.com/poouo/Forwardx/main/scripts/install-panel-local.sh")" == *"项目内置硬编码外部脚本源"* ]]
[[ "$(is_trusted_remote_script_url "https://us.arloor.dev/https://github.com/arloor/nftables-nat-rust/releases/download/v2.0.0/setup.sh")" == *"项目内置硬编码外部脚本源"* ]]
if is_trusted_remote_script_url "https://example.com/not-built-in.sh" >/dev/null; then
    echo "Unexpected trusted remote script URL." >&2
    exit 1
fi
remote_output=$(run_remote_script "smoke remote script" "file://$remote_script" 2>&1 <<< $'\n')
[[ "$remote_output" == *"非内置已知来源"* ]]
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

assert_file_contains vps.sh 'scripts/modules.list' "Source checkout entrypoint must read scripts/modules.list."
assert_file_contains vps.sh 'src/${module}.sh' "Source checkout entrypoint must source modules from src."
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
grep -Fq '是否继续下载并执行该远程脚本？(Y/n，默认 yes):' dist/vps.sh
assert_file_contains "src/environment.sh" '安装 nftables NAT 转发工具' "Environment menu must install nftables-nat-rust from option 10."
assert_file_not_contains "src/environment.sh" '哪吒监控' "Environment menu option 10 must not keep the old Nezha entry."
assert_file_not_contains "dist/vps.sh" 'raw.githubusercontent.com/naiba/nezha/master/script/install.sh' "Release script must not keep the old Nezha install URL."
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
10|修改 443 共享参数|edit_sni_stack_runtime_profile; continue ;;
11|订阅链接 / External Proxy 提示|check_sni_stack_subscription_hint ;;
12|CF DNS / Caddy 证书维护|func_caddy_cf_maintenance_menu; continue ;;
13|443 链路体检|sni_stack_health_check_enhanced ;;
14|443 网络访问测试|func_443_network_test; continue ;;
15|Xray 入站管理|manage_xray_inbound_routes; continue ;;
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
    "tutorials/01-3x-ui-reality-443.md"
    "tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md"
)
for file in "${docs_menu_files[@]}"; do
    assert_file_not_contains "$file" '主菜单 [18 443 单入口管理中心]' "${file} must not point users to the old main menu [18] 443 entry."
    assert_file_not_contains "$file" '主菜单 [14 服务健康总览]' "${file} must not point users to the old main menu [14] health entry."
    assert_file_not_contains "$file" '[15 配置备份与回滚]' "${file} must not point users to the old backup menu [15]."
done

renumbered_sni_doc_files=(
    "docs/443-single-entry-troubleshooting.md"
    "docs/config-paths.md"
    "docs/existing-server-migration.md"
    "docs/recovery-runbook.md"
    "tutorials/01-3x-ui-reality-443.md"
    "tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md"
)
for file in "${renumbered_sni_doc_files[@]}"; do
    assert_file_not_contains "$file" '主菜单 [19 443 单入口管理中心] -> [11 443 链路体检]' "${file} must use [13 443 链路体检]."
    assert_file_not_contains "$file" '主菜单 [19 443 单入口管理中心] -> [13 CF DNS / Caddy 证书维护]' "${file} must use [12 CF DNS / Caddy 证书维护]."
    assert_file_not_contains "$file" '主菜单 [19 443 单入口管理中心] -> [14 修改 443 共享参数]' "${file} must use [10 修改 443 共享参数]."
    assert_file_not_contains "$file" '主菜单 [19 443 单入口管理中心] -> [15 订阅链接 / External Proxy 提示]' "${file} must use [11 订阅链接 / External Proxy 提示]."
done

assert_file_contains "docs/443-single-entry.md" '3x-ui v3.4.0 及之后：左侧侧边栏 -> `Hosts / 主机` -> 新增 Host' "443 tutorial must document the 3x-ui v3.4.0+ Hosts path."
assert_file_contains "docs/443-single-entry.md" '3x-ui v3.3.1 及之前：在对应 REALITY 入站里打开 `External Proxy`' "443 tutorial must keep the legacy External Proxy path."
assert_file_contains "tutorials/01-3x-ui-reality-443.md" '3x-ui v3.4.0 及之后：左侧侧边栏 -> `Hosts / 主机` -> 新增 Host' "REALITY tutorial must document the 3x-ui v3.4.0+ Hosts path."
assert_file_contains "tutorials/01-3x-ui-reality-443.md" '3x-ui v3.3.1 及之前：在 REALITY 入站里打开 `External Proxy`' "REALITY tutorial must keep the legacy External Proxy path."
assert_file_contains "docs/443-single-entry-troubleshooting.md" '3x-ui v3.4.0 及之后：左侧侧边栏 -> `Hosts / 主机` -> 新增 Host' "Troubleshooting docs must document the 3x-ui v3.4.0+ Hosts path."
assert_file_contains "src/sni_stack_health.sh" '3x-ui v3.4.0 及之后：左侧侧边栏 -> Hosts / 主机 -> 新增 Host：' "Subscription hint must mention the 3x-ui v3.4.0+ Hosts path."
assert_dist_contains '3x-ui v3.4.0 及之后：左侧侧边栏 -> Hosts / 主机 -> 新增 Host：' "Built script must include the 3x-ui v3.4.0+ Hosts hint."

assert_file_not_contains "docs/443-single-entry.md" '主菜单 [3] -> [13] Caddy 反代' "443 tutorial must not point users to the old Caddy menu path."
assert_file_not_contains "docs/443-single-entry.md" '[19] -> [2] -> [5]' "443 tutorial must not point Web whitelist users to the old nested whitelist path."
assert_file_not_contains "docs/443-single-entry.md" '主菜单 [19 443 单入口管理中心] -> [9 管理 Web 域名 IP 白名单]' "443 tutorial must not point Web whitelist users to the stale direct [19] -> [9] path."

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

assert_file_contains ".github/ISSUE_TEMPLATE/bug_report.md" '主菜单 [19 443 单入口管理中心] -> [2 首次配置 / 安装 443 单入口]' "Bug report template must show the current 443 menu path."
assert_file_contains ".github/ISSUE_TEMPLATE/bug_report.md" '主菜单 [15 服务健康总览]' "Bug report template must show the current health menu path."
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
    "tutorials/01-3x-ui-reality-443.md"
)
for file in "${single_entry_mode_doc_files[@]}"; do
    assert_file_not_contains "$file" '公网 `443` 应只由 Nginx stream 监听' "${file} must not describe Nginx stream as the only possible public 443 listener."
    assert_file_not_contains "$file" '公网 `443` 只应由 Nginx stream 监听' "${file} must not describe Nginx stream as the only possible public 443 listener."
    assert_file_not_contains "$file" '公网 `443` 只给 Nginx stream' "${file} must not describe Nginx stream as the only possible public 443 listener."
    assert_file_not_contains "$file" '公网 `443` 只交给 Nginx stream' "${file} must not describe Nginx stream as the only possible public 443 listener."
done
assert_file_not_contains "tutorials/01-3x-ui-reality-443.md" '| Nginx 公网监听地址 |' "3x-ui REALITY tutorial must not show Nginx as the fixed public 443 listener."
assert_file_not_contains "tutorials/01-3x-ui-reality-443.md" '| 公网 `443` | Nginx stream 监听 |' "3x-ui REALITY tutorial must not expect public 443 to always be Nginx stream."
assert_file_not_contains "tutorials/01-3x-ui-reality-443.md" '可以先保留当前访问方式' "3x-ui REALITY tutorial must not defer panel loopback binding until after 443 works."
assert_file_not_contains "docs/443-single-entry.md" '默认 Nginx Stream 架构是：' "443 tutorial opening must describe the current entry-mode model, not the old Nginx-only default diagram."
assert_file_not_contains "docs/443-single-entry.md" '公网 443 -> Nginx stream 按 SNI 分流' "443 tutorial opening must not show Nginx stream as the fixed public 443 path."
assert_file_contains "docs/443-single-entry.md" '公网 443 -> 当前 ENTRY_MODE 对应的单个入口服务' "443 tutorial opening must show the current single-listener entry-mode chain."
assert_file_not_contains "docs/443-single-entry.md" 'Caddy 监听：127.0.0.1:8443' "443 tutorial examples must not pin the local Web reverse proxy listener to Caddy."
assert_file_not_contains "tutorials/01-3x-ui-reality-443.md" 'panel.example.com  -> Caddy 127.0.0.1:8443' "3x-ui REALITY tutorial must not pin panel Web backend to Caddy 127.0.0.1:8443."
assert_file_not_contains "tutorials/01-3x-ui-reality-443.md" 'panel.example.com/sub/ -> Caddy ->' "3x-ui REALITY tutorial must not pin subscription Web backend to Caddy."
assert_file_contains "tutorials/01-3x-ui-reality-443.md" 'panel.example.com  -> 当前 Web 反代引擎（Caddy 或 Nginx，例如 127.0.0.1:8443）' "3x-ui REALITY tutorial must describe the selectable local Web reverse proxy engine."
assert_file_contains "tutorials/01-3x-ui-reality-443.md" '如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，脚本只在兼容读取旧配置时按 `nginx-stream` 处理' "3x-ui REALITY tutorial must document ENTRY_MODE fallback compatibility."
assert_file_contains "docs/config-paths.md" '如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，脚本按 `nginx-stream` 兼容读取' "Config paths doc must document ENTRY_MODE fallback compatibility."
assert_file_contains "docs/443-single-entry-troubleshooting.md" '公网 `443` 只应由当前 `ENTRY_MODE` 对应的单个入口服务监听' "Troubleshooting doc must describe the current entry-mode listener model."
assert_file_contains "docs/dog.md" '不是商家账单级统计' "dog.sh docs must not imply bill-grade traffic accounting accuracy."
assert_file_contains "docs/dog.md" '不建议用它和 VPS 商家面板做精确对账' "dog.sh docs must steer users away from bill-grade reconciliation."
assert_file_contains "docs/dog.md" '商家后台仍应作为账单参考' "dog.sh docs must keep provider billing as the final reference."
assert_file_not_contains "docs/dog.md" '账单级准确' "dog.sh docs must not claim bill-grade accuracy."
assert_file_not_contains "docs/dog.md" '可作为账单依据' "dog.sh docs must not present dog.sh data as billing evidence."
assert_file_not_contains "docs/dog.md" '可替代商家账单' "dog.sh docs must not present dog.sh data as a provider-bill replacement."

assert_file_contains "docs/xui-custom-manager.md" '支持 3x-ui 2.9.x 和 3.x。' "xui-custom-manager docs must state the supported version ranges."
assert_file_contains "docs/xui-custom-manager.md" '写库前必须通过只读数据库 schema 检查' "xui-custom-manager docs must require schema checks before writes."
assert_file_contains "docs/xui-custom-manager.md" '不要跳过版本范围和 schema 检查强行写库' "xui-custom-manager docs must keep writes gated by version range and schema."
assert_file_not_contains "docs/xui-custom-manager.md" '只有 3x-ui v2.9.4 验证过写库操作。' "xui-custom-manager docs must not keep the old single-version write gate."
assert_file_not_contains "docs/xui-custom-manager.md" '未验证版本可能可用' "xui-custom-manager docs must not imply unsupported 3x-ui versions may work."
assert_file_not_contains "docs/xui-custom-manager.md" '其它版本也可能兼容' "xui-custom-manager docs must not imply unsupported 3x-ui versions may work."
assert_file_not_contains "docs/xui-custom-manager.md" '其它版本可尝试写库' "xui-custom-manager docs must not permit write trials on other 3x-ui versions."

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
grep -Fq 'S-UI 面板脚本' dist/vps.sh
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
grep -q 'OnActiveSec=${interval}s' dist/vps.sh
grep -q 'TRAFFIC_GUARD_CONFIG=' dist/vps.sh
grep -q 'traffic_guard_detect_initial_used_bytes' dist/vps.sh
grep -q 'traffic_guard_write_state_baseline' dist/vps.sh
grep -q 'traffic_guard_baseline_direction_offsets' dist/vps.sh
grep -q 'OFFSET_RX_BYTES' dist/vps.sh
grep -q 'direction_usage_at_last_check' dist/vps.sh
grep -q 'traffic_guard_sys_class_net' dist/vps.sh
grep -q 'boot_started_after_cycle_start' dist/vps.sh
grep -q 'cycle floor applied on ${IFACE}' dist/vps.sh
grep -q 'traffic_guard_live_usage_from_state' dist/vps.sh
grep -q 'print_traffic_guard_diagnostic_summary' dist/vps.sh
grep -q 'traffic_guard_recent_log_summary' dist/vps.sh
grep -q 'traffic_guard_admin_log' dist/vps.sh
grep -q 'traffic_guard_normalize_generated_checker' dist/vps.sh
grep -q 'traffic_guard_install_checker_once' dist/vps.sh
grep -q 'traffic_guard_install_checker_or_report' dist/vps.sh
grep -q 'retry checker install once after generated content validation failure' dist/vps.sh
grep -q '首行实际字节' dist/vps.sh
grep -q 'checker install failed:' dist/vps.sh
grep -q 'traffic_guard_run_checker_once' dist/vps.sh
grep -q 'sync_traffic_guard_now' dist/vps.sh
grep -q 'timer active 但状态文件已超过' dist/vps.sh
grep -q '最近 vps-traffic-guard 日志' dist/vps.sh
grep -q 'repair_traffic_guard_timer' dist/vps.sh
grep -q '最近检查超时' dist/vps.sh
grep -q '立即同步/验证检查器' dist/vps.sh
grep -Fq 'ExecStart=/usr/bin/env bash ${TRAFFIC_GUARD_CHECKER}' dist/vps.sh
grep -q '本周期已用 .*实时估算' dist/vps.sh
grep -q '网卡原始计数 .*不等于本周期已用' dist/vps.sh
grep -q '保护触发只看“本周期已用”' dist/vps.sh
grep -Fq 'OFFSET_RX_BYTES=$(( ${previous_direction_usage[0]:-0} + CURRENT_RX ))' dist/vps.sh
grep -q '本次重新配置默认按当前网卡原始计数估算' dist/vps.sh
grep -q 'traffic_guard_gb_to_bytes_zero_ok' dist/vps.sh
grep -q 'traffic_guard_cycle_date_for_month' dist/vps.sh
grep -q 'cycle_date_for_month' dist/vps.sh
grep -q '每月套餐/账单重置日 1-31' dist/vps.sh
grep -q 'guard_exit()' dist/vps.sh
grep -q 'checker exited unexpectedly rc=' dist/vps.sh
grep -q 'reset_traffic_guard_failed_state' dist/vps.sh
grep -q 'systemctl reset-failed vps-traffic-guard.service vps-traffic-guard.timer' dist/vps.sh
grep -q 'poweroff command accepted' dist/vps.sh
grep -q 'poweroff command failed; will retry on next timer run' dist/vps.sh
if grep -q '重置日只支持 1-28' dist/vps.sh; then
    echo "Traffic guard reset day must support 1-31." >&2
    exit 1
fi
grep -q 'counter reset detected on ${IFACE}, baseline reset and preserved current counters' dist/vps.sh
grep -q 'traffic|quota|bill|流量|达量|账单) echo "10"' dist/vps.sh
traffic_guard_menu_path='主菜单 [10 网络与内核优化] -> [5 流量达量关机保护]'
assert_file_contains CHANGELOG.md "$traffic_guard_menu_path" "CHANGELOG must document the current traffic guard menu path."
assert_file_contains src/menus.sh '10 -> 5  流量达量关机保护' "Menu help must keep traffic guard under network/kernel option 10 -> 5."
assert_file_not_contains CHANGELOG.md '[9 网络与内核优化] -> [7]' "CHANGELOG must not keep the stale traffic guard menu path."
if grep -q '20\..*流量达量关机保护' dist/vps.sh; then
    echo "Traffic guard must stay in the network submenu, not the main menu." >&2
    exit 1
fi

(
    source src/traffic_guard.sh
    tmp=$(mktemp -d /tmp/vps-traffic-guard-diag-smoke.XXXXXX)
    fake_sys="${tmp}/sys-class-net"
    config="${tmp}/traffic-guard.conf"
    state_dir="${tmp}/state"
    log_file="${tmp}/traffic-guard.log"
    iface="eth-diag0"
    current_cycle=$(traffic_guard_current_cycle_key 1)
    TRAFFIC_GUARD_CONFIG="$config"
    TRAFFIC_GUARD_STATE_DIR="$state_dir"
    TRAFFIC_GUARD_LOG="$log_file"
    VPSO_TRAFFIC_GUARD_SYS_CLASS_NET="$fake_sys"
    mkdir -p "${fake_sys}/${iface}/statistics" "$state_dir"
    printf 'up\n' > "${fake_sys}/${iface}/operstate"
    printf '1700\n' > "${fake_sys}/${iface}/statistics/rx_bytes"
    printf '2600\n' > "${fake_sys}/${iface}/statistics/tx_bytes"
    cat > "$config" <<EOF
ENABLED='1'
IFACE='${iface}'
MODE='total'
LIMIT_GB='0.00001'
LIMIT_BYTES='10000'
CYCLE_DAY='1'
WARN_PERCENT='90'
ACTION='log'
INITIAL_USED_GB='0'
INITIAL_USED_BYTES='0'
CHECK_INTERVAL='60'
EOF
    cat > "${state_dir}/state" <<EOF
CYCLE_KEY='${current_cycle}'
STATE_IFACE='${iface}'
STATE_MODE='total'
BASE_RX='1000'
BASE_TX='2000'
OFFSET_RX_BYTES='100'
OFFSET_TX_BYTES='200'
OFFSET_BYTES='300'
WARN_SENT='0'
TRIPPED='0'
LAST_RX='1500'
LAST_TX='2400'
LAST_USAGE='900'
LAST_CHECKED_AT='2000-01-01T00:00:00+00:00'
EOF
    printf '%s\n' 'old line' 'quota reached 900/10000 bytes on eth-diag0, mode=total, action=log' > "$log_file"
    systemctl() {
        case "$1" in
            is-active) [[ "$2" == "vps-traffic-guard.timer" ]] && printf '%s\n' "active" ;;
            is-enabled) [[ "$2" == "vps-traffic-guard.timer" ]] && printf '%s\n' "enabled" ;;
            *) return 1 ;;
        esac
    }
    traffic_guard_diag_output=$(print_traffic_guard_diagnostic_summary 2 yes 2>&1)
    grep -Fq 'timer: vps-traffic-guard.timer active=active; enabled=enabled' <<<"$traffic_guard_diag_output"
    grep -Fq "配置文件: ${config} (存在)" <<<"$traffic_guard_diag_output"
    grep -Fq "状态文件: ${state_dir}/state (存在)" <<<"$traffic_guard_diag_output"
    grep -Fq "日志文件: ${log_file} (存在)" <<<"$traffic_guard_diag_output"
    grep -Fq '模式=出入总量 RX+TX' <<<"$traffic_guard_diag_output"
    grep -Fq '实时估算:' <<<"$traffic_guard_diag_output"
    grep -Fq '方向估算: RX' <<<"$traffic_guard_diag_output"
    grep -Fq 'timer active 但状态文件已超过' <<<"$traffic_guard_diag_output"
    grep -Fq '最近 vps-traffic-guard 日志:' <<<"$traffic_guard_diag_output"
    grep -Fq 'quota reached 900/10000 bytes on eth-diag0' <<<"$traffic_guard_diag_output"
)

(
    source src/traffic_guard.sh
    tmp=$(mktemp -d /tmp/vps-traffic-guard-install-smoke.XXXXXX)
    TRAFFIC_GUARD_CHECKER="${tmp}/vps-traffic-guard-check"
    TRAFFIC_GUARD_CONFIG="${tmp}/traffic-guard.conf"
    TRAFFIC_GUARD_STATE_DIR="${tmp}/state"
    TRAFFIC_GUARD_LOG="${tmp}/traffic-guard.log"

    install_traffic_guard_checker
    head -n 1 "$TRAFFIC_GUARD_CHECKER" | grep -Fq '#!/usr/bin/env bash'
    bash -n "$TRAFFIC_GUARD_CHECKER"
    [[ -x "$TRAFFIC_GUARD_CHECKER" ]]
    grep -Fq "checker installed: ${TRAFFIC_GUARD_CHECKER}" "$TRAFFIC_GUARD_LOG"
)

traffic_guard_install_failure_regression() {
    local case_name="$1"
    local expected_reason="$2"
    (
        # shellcheck disable=SC1091
        source src/traffic_guard.sh
        tmp=$(mktemp -d /tmp/vps-traffic-guard-install-fail-smoke.XXXXXX)
        TRAFFIC_GUARD_CHECKER="${tmp}/vps-traffic-guard-check"
        TRAFFIC_GUARD_CONFIG="${tmp}/traffic-guard.conf"
        TRAFFIC_GUARD_STATE_DIR="${tmp}/state"
        TRAFFIC_GUARD_LOG="${tmp}/traffic-guard.log"
        printf '%s\n' '#!/usr/bin/env bash' 'printf "stable-live-checker\n"' > "$TRAFFIC_GUARD_CHECKER"
        chmod 700 "$TRAFFIC_GUARD_CHECKER"

        case "$case_name" in
            shebang)
                traffic_guard_normalize_generated_checker() {
                    sed -i '1c#!/bin/sh' "$1"
                }
                ;;
            crlf)
                traffic_guard_normalize_generated_checker() {
                    printf '\r' >> "$1"
                }
                ;;
            syntax)
                traffic_guard_normalize_generated_checker() {
                    printf '\nif (\n' >> "$1"
                }
                ;;
            *)
                echo "Unknown Traffic Guard install failure case: ${case_name}" >&2
                exit 1
                ;;
        esac

        if output=$(install_traffic_guard_checker 2>&1); then
            echo "Traffic Guard ${case_name} install smoke must fail." >&2
            exit 1
        fi
        grep -Fq "$expected_reason" <<<"$output"
        grep -Fq "首行实际字节" <<<"$output"
        grep -Fq "检查器生成内容异常，正在安全重装一次" <<<"$output"
        retry_count=$(grep -Fc "retry checker install once after generated content validation failure" "$TRAFFIC_GUARD_LOG" || true)
        [[ "$retry_count" == "1" ]]
        head -n 1 "$TRAFFIC_GUARD_CHECKER" | grep -Fq '#!/usr/bin/env bash'
        grep -Fq 'stable-live-checker' "$TRAFFIC_GUARD_CHECKER"
        bash -n "$TRAFFIC_GUARD_CHECKER"
    )
}

traffic_guard_install_failure_regression shebang '首行必须是 #!/usr/bin/env bash'
traffic_guard_install_failure_regression crlf '检测到 CRLF/回车字符'
traffic_guard_install_failure_regression syntax 'Bash 语法检查未通过'

(
    # shellcheck disable=SC1091
    source src/traffic_guard.sh
    tmp=$(mktemp -d /tmp/vps-traffic-guard-report-smoke.XXXXXX)
    TRAFFIC_GUARD_CHECKER="${tmp}/vps-traffic-guard-check"
    TRAFFIC_GUARD_CONFIG="${tmp}/traffic-guard.conf"
    TRAFFIC_GUARD_STATE_DIR="${tmp}/state"
    TRAFFIC_GUARD_LOG="${tmp}/traffic-guard.log"
    install_traffic_guard_checker() {
        return 1
    }
    systemctl() {
        printf 'fake systemctl %s\n' "$*"
    }
    journalctl() {
        printf 'fake journal\n'
    }
    if output=$(traffic_guard_install_checker_or_report 2>&1); then
        echo "Traffic Guard install report helper must fail when checker install fails." >&2
        exit 1
    fi
    grep -Fq "安装检查脚本失败。下面是可直接排查的上下文" <<<"$output"
    grep -Fq "Traffic Guard 检查器/Timer 诊断上下文" <<<"$output"
    grep -Fq "checker : ${TRAFFIC_GUARD_CHECKER}" <<<"$output"
)

traffic_guard_checker_menu_path_regression() {
    (
        # shellcheck disable=SC1091
        source src/traffic_guard.sh
        local tmp state_file old_checked call_log systemctl_calls output sync_output fail_output install_fail_output last_checked

        tmp=$(mktemp -d /tmp/vps-traffic-guard-menu-smoke.XXXXXX)
        TRAFFIC_GUARD_CHECKER="${tmp}/vps-traffic-guard-check"
        TRAFFIC_GUARD_CONFIG="${tmp}/traffic-guard.conf"
        TRAFFIC_GUARD_STATE_DIR="${tmp}/state"
        TRAFFIC_GUARD_LOG="${tmp}/traffic-guard.log"
        state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
        old_checked='2000-01-01T00:00:00+00:00'
        call_log="${tmp}/calls.log"
        systemctl_calls="${tmp}/systemctl.log"

        traffic_guard_write_stale_menu_state() {
            mkdir -p "$TRAFFIC_GUARD_STATE_DIR"
            cat > "$state_file" <<EOF
LAST_CHECKED_AT='${old_checked}'
EOF
        }

        traffic_guard_write_refreshing_checker() {
            mkdir -p "$(dirname "$TRAFFIC_GUARD_CHECKER")"
            cat > "$TRAFFIC_GUARD_CHECKER" <<EOF
#!/usr/bin/env bash
mkdir -p '${TRAFFIC_GUARD_STATE_DIR}'
cat > '${state_file}' <<STATE
LAST_CHECKED_AT='\$(date -Is 2>/dev/null || date)'
STATE
EOF
            chmod +x "$TRAFFIC_GUARD_CHECKER"
        }

        traffic_guard_write_noop_checker() {
            mkdir -p "$(dirname "$TRAFFIC_GUARD_CHECKER")"
            printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TRAFFIC_GUARD_CHECKER"
            chmod +x "$TRAFFIC_GUARD_CHECKER"
        }

        load_traffic_guard_config() {
            ACTION='log'
            IFACE='eth-menu0'
            CHECK_INTERVAL='45'
            return 0
        }
        confirm_risk_action() { return 0; }
        confirm_danger() { return 0; }
        pause_return() { :; }
        show_traffic_guard_status() { printf '%s\n' 'STATUS_SHOWN'; }
        journalctl() { printf '%s\n' 'fake journal'; }
        systemctl() {
            printf '%s\n' "$*" >> "$systemctl_calls"
            case "$1" in
                list-unit-files) return 1 ;;
                *) return 0 ;;
            esac
        }

        traffic_guard_write_stale_menu_state
        install_traffic_guard_checker() {
            printf '%s\n' 'install-checker' >> "$call_log"
            traffic_guard_write_refreshing_checker
        }
        install_traffic_guard_units() {
            printf 'install-units %s\n' "$1" >> "$call_log"
            [[ "$1" == "45" ]]
        }
        output=$(repair_traffic_guard_timer 2>&1)
        grep -Fxq 'install-checker' "$call_log"
        grep -Fxq 'install-units 45' "$call_log"
        grep -Fq 'restart vps-traffic-guard.timer' "$systemctl_calls"
        last_checked=$(traffic_guard_state_last_checked_at)
        if [[ "$last_checked" == "$old_checked" ]]; then
            echo "Traffic Guard timer repair must immediately run the checker and refresh state." >&2
            exit 1
        fi

        traffic_guard_write_stale_menu_state
        traffic_guard_write_refreshing_checker
        sync_output=$(sync_traffic_guard_now 2>&1)
        grep -Fq 'STATUS_SHOWN' <<<"$sync_output"
        last_checked=$(traffic_guard_state_last_checked_at)
        if [[ "$last_checked" == "$old_checked" ]]; then
            echo "Traffic Guard immediate sync must refresh state before showing status." >&2
            exit 1
        fi

        traffic_guard_write_stale_menu_state
        install_traffic_guard_checker() {
            traffic_guard_write_noop_checker
        }
        install_traffic_guard_units() {
            return 0
        }
        if fail_output=$(repair_traffic_guard_timer 2>&1); then
            echo "Traffic Guard timer repair must fail when the checker does not refresh state." >&2
            exit 1
        fi
        grep -Fq "checker : ${TRAFFIC_GUARD_CHECKER}" <<<"$fail_output"
        grep -Fq "state   : ${state_file}" <<<"$fail_output"

        traffic_guard_write_stale_menu_state
        traffic_guard_write_noop_checker
        if fail_output=$(sync_traffic_guard_now 2>&1); then
            echo "Traffic Guard immediate sync must fail when the checker does not refresh state." >&2
            exit 1
        fi
        grep -Fq "checker : ${TRAFFIC_GUARD_CHECKER}" <<<"$fail_output"
        grep -Fq "state   : ${state_file}" <<<"$fail_output"

        install_traffic_guard_checker() {
            return 1
        }
        if install_fail_output=$(repair_traffic_guard_timer 2>&1); then
            echo "Traffic Guard timer repair must fail when checker reinstall fails." >&2
            exit 1
        fi
        grep -Fq "checker : ${TRAFFIC_GUARD_CHECKER}" <<<"$install_fail_output"
    )
}
traffic_guard_checker_menu_path_regression

traffic_guard_accounting_regression() {
    # shellcheck disable=SC1091
    source src/traffic_guard.sh
    local offsets usage_rx usage_tx usage
    local tmp fake_sys fake_proc fake_bin fake_calls guard config state_dir log_file iface current_cycle

    mapfile -t offsets < <(traffic_guard_baseline_direction_offsets max 1000 100 1000)
    usage_rx=$(( offsets[0] + 0 ))
    usage_tx=$(( offsets[1] + 900 ))
    usage=$(traffic_guard_mode_usage_bytes max "$usage_rx" "$usage_tx")
    if [[ "$usage" != "1000" ]]; then
        echo "max-mode traffic guard must keep RX/TX directional offsets after counter reset; got ${usage}." >&2
        exit 1
    fi

    mapfile -t offsets < <(traffic_guard_baseline_direction_offsets total 800 200 1000)
    usage=$(traffic_guard_mode_usage_bytes total "${offsets[0]}" "${offsets[1]}")
    if [[ "$usage" != "1000" ]]; then
        echo "total-mode traffic guard offsets must preserve the configured initial usage; got ${usage}." >&2
        exit 1
    fi

    tmp=$(mktemp -d /tmp/vps-traffic-guard-smoke.XXXXXX)
    fake_sys="${tmp}/sys-class-net"
    fake_proc="${tmp}/uptime"
    fake_bin="${tmp}/bin"
    fake_calls="${tmp}/poweroff-calls.log"
    guard="${tmp}/checker"
    config="${tmp}/traffic-guard.conf"
    state_dir="${tmp}/state"
    log_file="${tmp}/traffic-guard.log"
    iface="eth-smoke0"
    printf '999999999 0\n' > "$fake_proc"
    mkdir -p "$fake_bin"
    awk "/<<'GUARD_SCRIPT'/{flag=1; next} /^GUARD_SCRIPT$/{flag=0} flag {print}" src/traffic_guard.sh > "$guard"
    chmod +x "$guard"
    current_cycle=$(traffic_guard_current_cycle_key 1)

    traffic_guard_write_fake_iface() {
        local sys_dir="$1" test_iface="$2" rx="$3" tx="$4"
        mkdir -p "${sys_dir}/${test_iface}/statistics"
        printf 'up\n' > "${sys_dir}/${test_iface}/operstate"
        printf '%s\n' "$rx" > "${sys_dir}/${test_iface}/statistics/rx_bytes"
        printf '%s\n' "$tx" > "${sys_dir}/${test_iface}/statistics/tx_bytes"
    }

    traffic_guard_write_smoke_config() {
        local action="${1:-log}" limit_bytes="${2:-1000000000}" initial_bytes="${3:-0}"
        cat > "$config" <<EOF
ENABLED='1'
IFACE='${iface}'
MODE='tx'
LIMIT_GB='1'
LIMIT_BYTES='${limit_bytes}'
CYCLE_DAY='1'
WARN_PERCENT='90'
ACTION='${action}'
INITIAL_USED_GB='0'
INITIAL_USED_BYTES='${initial_bytes}'
CHECK_INTERVAL='60'
EOF
    }

    traffic_guard_run_smoke_checker() {
        VPSO_TRAFFIC_GUARD_CONFIG="$config" \
        VPSO_TRAFFIC_GUARD_STATE_DIR="$state_dir" \
        VPSO_TRAFFIC_GUARD_LOG="$log_file" \
        VPSO_TRAFFIC_GUARD_SYS_CLASS_NET="$fake_sys" \
        VPSO_TRAFFIC_GUARD_PROC_UPTIME="$fake_proc" \
        "$guard"
    }

    TRAFFIC_GUARD_STATE_DIR="$state_dir"
    VPSO_TRAFFIC_GUARD_SYS_CLASS_NET="$fake_sys"
    VPSO_TRAFFIC_GUARD_PROC_UPTIME="$fake_proc"

    traffic_guard_write_fake_iface "$fake_sys" "$iface" 100000 9000000
    traffic_guard_write_state_baseline "$iface" 1 1000 tx
    traffic_guard_write_fake_iface "$fake_sys" "$iface" 100000 9000500
    traffic_guard_write_smoke_config log 1000000000 1000
    traffic_guard_run_smoke_checker
    # shellcheck disable=SC1090
    source "${state_dir}/state"
    if [[ "${LAST_USAGE:-}" != "1500" ]]; then
        echo "Traffic guard first baseline must preserve manual initial usage plus post-baseline delta; got ${LAST_USAGE:-unset}." >&2
        exit 1
    fi

    traffic_guard_write_fake_iface "$fake_sys" "$iface" 1200 3400
    mkdir -p "$state_dir"
    cat > "${state_dir}/state" <<EOF
CYCLE_KEY='2000-01-01'
STATE_IFACE='${iface}'
STATE_MODE='tx'
BASE_RX='100'
BASE_TX='200'
OFFSET_RX_BYTES='0'
OFFSET_TX_BYTES='0'
OFFSET_BYTES='0'
WARN_SENT='1'
TRIPPED='1'
LAST_RX='1000'
LAST_TX='3000'
LAST_USAGE='2800'
LAST_CHECKED_AT='2000-01-01T00:00:00+00:00'
EOF
    traffic_guard_write_smoke_config log 1000000000 0
    traffic_guard_run_smoke_checker
    # shellcheck disable=SC1090
    source "${state_dir}/state"
    if [[ "${CYCLE_KEY:-}" != "$current_cycle" || "${BASE_TX:-}" != "3400" || "${LAST_USAGE:-}" != "0" || "${WARN_SENT:-}" != "0" || "${TRIPPED:-}" != "0" ]]; then
        echo "Traffic guard must reset baseline cleanly across billing cycles; cycle=${CYCLE_KEY:-unset} base_tx=${BASE_TX:-unset} usage=${LAST_USAGE:-unset}." >&2
        exit 1
    fi

    traffic_guard_write_fake_iface "$fake_sys" "$iface" 10 100
    cat > "${state_dir}/state" <<EOF
CYCLE_KEY='${current_cycle}'
STATE_IFACE='${iface}'
STATE_MODE='tx'
BASE_RX='1000'
BASE_TX='10000'
OFFSET_RX_BYTES='0'
OFFSET_TX_BYTES='200'
OFFSET_BYTES='200'
WARN_SENT='0'
TRIPPED='0'
LAST_RX='1500'
LAST_TX='12000'
LAST_USAGE='2200'
LAST_CHECKED_AT='${current_cycle}T00:00:00+00:00'
EOF
    traffic_guard_write_smoke_config log 1000000000 0
    traffic_guard_run_smoke_checker
    # shellcheck disable=SC1090
    source "${state_dir}/state"
    if [[ "${BASE_TX:-}" != "100" || "${OFFSET_TX_BYTES:-}" != "2300" || "${LAST_USAGE:-}" != "2300" ]]; then
        echo "Traffic guard must preserve usage after counter reset/wrap; base_tx=${BASE_TX:-unset} offset_tx=${OFFSET_TX_BYTES:-unset} usage=${LAST_USAGE:-unset}." >&2
        exit 1
    fi

    for cmd in systemctl poweroff shutdown sync logger; do
        cat > "${fake_bin}/${cmd}" <<EOF
#!/usr/bin/env bash
case "\${0##*/}" in
    sync|logger) exit 0 ;;
    *) printf '%s %s\n' "\${0##*/}" "\$*" >> "${fake_calls}"; exit 1 ;;
esac
EOF
        chmod +x "${fake_bin}/${cmd}"
    done
    traffic_guard_write_fake_iface "$fake_sys" "$iface" 0 2000
    cat > "${state_dir}/state" <<EOF
CYCLE_KEY='${current_cycle}'
STATE_IFACE='${iface}'
STATE_MODE='tx'
BASE_RX='0'
BASE_TX='0'
OFFSET_RX_BYTES='0'
OFFSET_TX_BYTES='0'
OFFSET_BYTES='0'
WARN_SENT='0'
TRIPPED='0'
LAST_RX='0'
LAST_TX='0'
LAST_USAGE='0'
LAST_CHECKED_AT='${current_cycle}T00:00:00+00:00'
EOF
    traffic_guard_write_smoke_config poweroff 1000 0
    PATH="${fake_bin}:$PATH" traffic_guard_run_smoke_checker
    # shellcheck disable=SC1090
    source "${state_dir}/state"
    if [[ "${LAST_USAGE:-}" != "2000" || "${TRIPPED:-}" != "0" ]]; then
        echo "Traffic guard poweroff failure must keep retry state honest; usage=${LAST_USAGE:-unset} tripped=${TRIPPED:-unset}." >&2
        exit 1
    fi
    grep -q 'poweroff command failed; will retry on next timer run' "$log_file"
    grep -q '^systemctl poweroff$' "$fake_calls"
    grep -q '^poweroff $' "$fake_calls"
    grep -q '^shutdown -h now$' "$fake_calls"
}
traffic_guard_accounting_regression

grep -q 'curl_rc=' dist/vps.sh
if grep -q 'HTTP ${code}${PLAIN}' dist/vps.sh && grep -q '|| echo "000"' dist/vps.sh; then
    echo "443 curl probe must not concatenate fallback HTTP 000 values." >&2
    exit 1
fi
traffic_guard_dist_checker_template=$(awk "/<<'GUARD_SCRIPT'/{flag=1; next} /^GUARD_SCRIPT$/{flag=0} flag {print}" dist/vps.sh)
head -n 1 <<<"$traffic_guard_dist_checker_template" | grep -Fq '#!/usr/bin/env bash'
bash -n <<<"$traffic_guard_dist_checker_template"
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
grep -q '密钥 + 密码登录（保留/恢复密码）' dist/vps.sh
grep -q '添加/更新用户 SSH 公钥（不改登录方式）' dist/vps.sh
if grep -Fq '4. 恢复密码登录' dist/vps.sh || grep -Fq '4) ssh_apply_auth_mode password' dist/vps.sh; then
    echo "SSH key login menu must not keep duplicate password-recovery entry." >&2
    exit 1
fi
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
grep -q '2. 查看/编辑 Compose 配置' dist/vps.sh
grep -q 'edit_applied_config_file "$compose_file" "compose"' dist/vps.sh
assert_file_contains "docs/config-paths.md" '主菜单 [16 配置备份与回滚] -> [5 查看/编辑脚本已应用配置]' "Config paths doc must list the global applied-config editor."
assert_file_contains "docs/443-single-entry.md" '[4] -> [5 域名 IP 白名单]' "443 doc must describe the combined Caddy/Nginx whitelist menu."
assert_file_contains "docs/443-single-entry.md" '主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]' "443 doc must describe the current 443 Web whitelist menu path."
assert_file_contains "src/caddy_proxy.sh" '主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]' "Nginx standalone whitelist guidance must point users to the current 443 Web whitelist submenu path."
assert_file_contains "src/caddy_maintenance.sh" '主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]' "Caddy standalone whitelist guidance must point users to the current 443 Web whitelist submenu path."
assert_file_contains "src/caddy_whitelist.sh" '主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]' "Compatibility Caddy whitelist guidance must point users to the current 443 Web whitelist submenu path."
assert_file_not_contains "src/caddy_proxy.sh" '[19] -> [9]' "Nginx standalone whitelist guidance must not point users to the stale direct [19] -> [9] path."
assert_file_not_contains "src/caddy_maintenance.sh" '[19] -> [9]' "Caddy standalone whitelist guidance must not point users to the stale direct [19] -> [9] path."
assert_file_not_contains "src/caddy_whitelist.sh" '[19] -> [9]' "Compatibility Caddy whitelist guidance must not point users to the stale direct [19] -> [9] path."
assert_file_contains "docs/443-single-entry.md" '[8 切换 Web 反代引擎]' "443 doc must document switching the Web reverse proxy engine."
assert_file_contains "docs/443-single-entry.md" 'Nginx 本地 Web 反代 | 不允许新增或覆盖 Web 白名单' "443 doc must prohibit unsupported Nginx fallback whitelist usage."
assert_file_contains "docs/443-tcp-peek-engine.md" 'Web 反代引擎可选择 Caddy 或 Nginx' "TCP Peek doc must describe the shared Caddy/Nginx Web proxy engine."
subscription_public_hint='公网 HTTPS 访问建议：未启用 443 单入口时，请走主菜单 [4 反代] 里的 Caddy 或 Nginx HTTPS 反代；已启用 443 单入口时，请走主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]。'
assert_file_contains "src/subscription_apps.sh" "$subscription_public_hint" "Subscription/Komari installers must explain both non-single-entry and 443 single-entry reverse proxy paths."
assert_dist_contains "$subscription_public_hint" "Release script must include the current Subscription/Komari public HTTPS guidance."
panel_menu_compact_label='Sing-box 脚本'
assert_file_contains "src/menus.sh" "$panel_menu_compact_label" "Panel/tools menu must use the compact script-style label."
assert_dist_contains "$panel_menu_compact_label" "Release script must include the compact panel/tools menu label."
panel_help_public_hint='7/8/9 订阅栈，11 Dockge Compose，12 Compose 迁移；公网 HTTPS：未启用 443 单入口走主菜单 [4 反代]，已启用走主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]。'
assert_file_contains "src/menus.sh" "$panel_help_public_hint" "Panel/tools help must explain both non-single-entry and 443 single-entry reverse proxy paths."
assert_dist_contains "$panel_help_public_hint" "Release script must include the current panel/tools help public HTTPS guidance."
panel_domain_menu_path='主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [9 修改面板域名]'
assert_file_contains "src/menus.sh" "$panel_domain_menu_path" "443 help must point panel-domain edits to the Web domain submenu."
assert_file_contains "src/sni_stack_profiles.sh" "$panel_domain_menu_path" "443 shared-parameters submenu must point panel-domain edits to the Web domain submenu."
assert_dist_contains "$panel_domain_menu_path" "Release script must include the current panel-domain edit path."
assert_file_not_contains "src/menus.sh" '共享参数可修改面板域名' "443 help must not say shared parameters modify the panel domain."
assert_file_not_contains "src/menus.sh" '面板域名、面板/订阅/REALITY/入口端口与路径' "443 menu label must not list panel domain under shared parameters."
assert_file_not_contains "src/sni_stack_profiles.sh" '用途：后续修改面板域名' "443 shared-parameters submenu purpose must not list panel domain."
assert_file_not_contains "src/sni_stack_profiles.sh" '4) edit_sni_stack_panel_domain_profile ;;' "443 shared-parameters submenu must not keep the old direct panel-domain action."
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
assert_file_contains "tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md" '主菜单 [4 反代]' "Subscription tutorial must point non-single-entry users at the current reverse proxy menu."
assert_file_contains "tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md" '[2 添加 Nginx HTTPS 反代]' "Subscription tutorial must document the Nginx HTTPS reverse proxy option before 443 single-entry is enabled."
assert_file_contains "tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md" '主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]' "Subscription tutorial must keep the current 443 single-entry Web reverse proxy path."
assert_file_contains "docs/existing-server-migration.md" '未启用 443 单入口时的 HTTPS 反代过渡' "Migration doc must include the non-single-entry HTTPS reverse proxy transition flow."
assert_file_contains "docs/existing-server-migration.md" '[2 添加 Nginx HTTPS 反代]' "Migration doc must document the Nginx HTTPS reverse proxy option before 443 single-entry is enabled."
for file in README.md docs/existing-server-migration.md tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md; do
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
grep -q '4) func_hosts_manage' dist/vps.sh
grep -q '4|网卡管理工具|网卡/路由/DNS/MTU/DHCP|func_network_interface_manage|' dist/vps.sh
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
