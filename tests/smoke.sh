#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Smoke failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ "${VPSO_CI_CONTAINER:-}" == "1" ]]; then
    git config --global --add safe.directory "$repo_root"
fi

bash tests/http-probes.sh

for ignored_artifact in \
    'etc/vps-optimize/backups/manual/backup_20260101_010203.tar.gz' \
    'etc/vps-optimize/backups/sni-stack_20260101_010203/nginx.conf' \
    'tmp/vps_backup_20260101_010203/manifest.txt' \
    'tmp/vps_restore.ABC123/manifest.txt' \
    'etc/vps-optimize/quarantine/manual-temp/vps_restore.ABC123/manifest.txt' \
    'etc/vps-optimize/quarantine/manual-restore/etc/x-ui/x-ui.db' \
    'etc/vps-optimize/quarantine/manual-backups/backup_20260101_010203.tar.gz' \
    'etc/x-ui/x-ui.db' \
    'etc/x-ui/x-ui.db-wal' \
    'etc/x-ui/x-ui.db-shm' \
    'usr/local/x-ui/x-ui.db' \
    'usr/local/x-ui/x-ui.db-wal' \
    'usr/local/x-ui/x-ui.db-shm' \
    'usr/local/x-ui/bin/x-ui.db' \
    'usr/local/x-ui/bin/x-ui.db-wal' \
    'usr/local/x-ui/bin/x-ui.db-shm' \
    'root/x-ui-backups/x-ui.db.panel_domain_20260101_010203.bak'
do
    git check-ignore --quiet -- "$ignored_artifact"
done
source src/language.sh
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
source src/menus.sh

(
    VPSO_LANGUAGE=zh
    clear() { :; }
    show_current_entry_summary() { :; }
    print_breadcrumb() { :; }
    print_menu_item() { :; }
    menu_handlers=(
        manage_entry_mode_install_or_switch manage_sni_stack_sites
        edit_sni_stack_runtime_profile manage_xray_inbound_routes
        manage_sni_stack_ip_whitelist manage_reality_traffic_guard
        func_caddy_cf_maintenance_menu update_vpso_mux_binary
        reapply_current_entry_mode rollback_last_entry_mode
        show_current_entry_status check_sni_stack_subscription_hint
        sni_stack_health_check_enhanced func_443_network_test view_current_entry_logs
    )
    for menu_index in "${!menu_handlers[@]}"; do
        menu_output=$(
            for handler in "${menu_handlers[@]}"; do
                eval "$handler() { echo '$handler'; exit 0; }"
            done
            func_sni_stack_quick_menu <<<"$((menu_index + 1))"
        )
        [[ "${menu_output##*$'\n'}" == "${menu_handlers[$menu_index]}" ]]
    done
    for back in 0 q Q ''; do
        func_sni_stack_quick_menu <<< $'invalid\n'"$back" >/dev/null
    done
)

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
[[ "$(normalize_menu_choice_input " 返回 ")" == "返回" ]]
[[ "$(normalize_menu_choice_input " １ ")" == "1" ]]
[[ "$(normalize_menu_choice_input "１０、")" == "10" ]]
[[ "$(normalize_menu_choice_input "2)")" == "2" ]]
[[ "$(LC_ALL=C normalize_menu_choice_input "１０、")" == "10" ]]
[[ "$(LC_ALL=C normalize_menu_choice_input "３．")" == "3" ]]
choice=""
read_trimmed choice "" <<< " 返回 "
[[ "$choice" == "返回" ]]
choice=""
read_trimmed choice "" <<< " Q "
[[ "$choice" == "0" ]]
action=""
read_trimmed action "" <<< "back"
[[ "$action" == "back" ]]
c=""
read_trimmed c "" <<< "３．"
[[ "$c" == "3" ]]
t=""
read_trimmed t "" <<< "退出"
[[ "$t" == "退出" ]]
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
confirm=""
read_trimmed confirm "确认操作？(Y/n): " <<< ""
[[ "$confirm" == "y" ]]
eof_confirm="sentinel"
if read_trimmed eof_confirm "确认操作？(Y/n): " </dev/null; then
    echo "Closed input must not accept a default confirmation." >&2
    exit 1
fi
[[ -z "$eof_confirm" ]]
confirm=""
read_trimmed confirm "Продолжить? (Да/Нет): " <<< ""
[[ "$confirm" == "y" ]]
colored_confirmation=$(colorize_confirmation_prompt "Proceed? (Y/n) Continue? (y/N)")
[[ "$colored_confirmation" == *$'\033[1;32mY'* ]]
[[ "$colored_confirmation" == *$'\033[1;31mn'* ]]
[[ "$colored_confirmation" == *$'\033[1;31my'* ]]
[[ "$colored_confirmation" == *$'\033[1;32mN'* ]]
[[ "$(NO_COLOR= bash -c 'source src/common.sh; printf "%s%s" "$GREEN" "$RED"')" == "" ]]
(
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    PLAIN=''
    [[ "$(terminal_text_width "中文")" == "4" ]]
    [[ "$(terminal_text_width "Русский")" == "7" ]]
    for menu_row in \
        "$(print_menu_item 1 "基础环境初始化" "中文说明")" \
        "$(print_menu_item 19 "443端口复用管理中心" "中文说明")" \
        "$(print_menu_item 1 "Preflight and risk scan" "English description")" \
        "$(print_menu_item 19 "Port 443 Reuse manager" "English description")" \
        "$(print_menu_item 1 "Предварительная проверка" "Описание")" \
        "$(print_menu_item 19 "Общий порт 443" "Описание")"; do
        [[ "$(terminal_text_width "${menu_row%%(*}")" == "35" ]]
    done

    for menu_row in \
        "$(print_menu_item 1 "入口状态" "说明" 27)" \
        "$(print_menu_item 17 "REALITY 流量防护" "说明" 27)"; do
        [[ "$(terminal_text_width "${menu_row%%(*}")" == "34" ]]
    done
    for menu_row in \
        "$(print_menu_item 1 "Entry status" "Description" 34)" \
        "$(print_menu_item 8 "Web domains and reverse proxies" "Description" 34)"; do
        [[ "$(terminal_text_width "${menu_row%%(*}")" == "41" ]]
    done
    for menu_row in \
        "$(print_menu_item 1 "Состояние входа" "Описание" 39)" \
        "$(print_menu_item 9 "Список разрешённых IP для Web" "Описание" 39)"; do
        [[ "$(terminal_text_width "${menu_row%%(*}")" == "46" ]]
    done
)
for shortcut_mapping in \
    'proxy:4' 'panel:5' 'ssh:6' 'firewall:8' 'bbr:10' 'docker:11' \
    'speed:12' 'health:15' 'backup:16' 'u:17' 'update:17' 'upd:17' '443:19' 'lang:20'; do
    shortcut=${shortcut_mapping%%:*}
    expected_choice=${shortcut_mapping#*:}
    [[ "$(normalize_main_choice "$shortcut")" == "$expected_choice" ]]
    [[ "$(normalize_main_choice "${shortcut^^}")" == "$expected_choice" ]]
done
for removed_shortcut in caddy nginx xcm traffic quota reboot docker-safe; do
    [[ "$(normalize_main_choice "$removed_shortcut")" == "$removed_shortcut" ]]
done
confirm_default_yes <<< ""
action_needs_safe_default "重启 SSH 服务" ""
action_needs_safe_default "Isolate certificate files" ""
action_needs_safe_default "Apply sysctl configuration" ""
action_needs_safe_default "Install 3x-ui" "download and run the official installer"
action_needs_safe_default "Deploy Sub-Store" "start a Compose project"
action_needs_safe_default "Перезапустить Docker" ""
action_needs_safe_default "Переключить режим входа" ""
if action_needs_safe_default "查看服务状态" "仅读取状态"; then
    echo "Read-only actions must keep the low-risk default." >&2
    exit 1
fi
danger_output=$(confirm_danger "重启服务" "重启测试服务" "再次启动服务" <<< $'\ny\nYES\n')
[[ "$danger_output" == *"参数已保留"* ]]
if confirm_danger "删除配置" "删除测试配置" "从备份恢复" <<< $'y\n\nn\n' >/dev/null; then
    echo "Blank final confirmation must return to the first confirmation instead of executing." >&2
    exit 1
fi
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
    source src/system_core.sh
    clear() { :; }
    print_breadcrumb() { :; }
    sleep() { :; }
    mirror_status=0
    mirror_call=()
    run_remote_script() { mirror_call=("$@"); return "$mirror_status"; }
    pause_after_external_script() { :; }
    for VPSO_LANGUAGE in zh en ru; do
        if [[ "$VPSO_LANGUAGE" == zh ]]; then mirror_language=zh; else mirror_language=en; fi
        UPDATE_MIRROR=https://mirror.example
        OS=debian
        for mirror_category in {1..7}; do
            mapfile -t mirror_entries < <(system_mirror_catalog "$mirror_category")
            for mirror_index in "${!mirror_entries[@]}"; do
                IFS='|' read -r mirror_zh mirror_en mirror_source <<<"${mirror_entries[mirror_index]}"
                func_system_mirrors <<< "$mirror_category"$'\n'"$((mirror_index + 1))" >/dev/null
                [[ "${mirror_call[1]}" == https://mirror.example/https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh ]]
                [[ "${mirror_call[*]:2:4}" == "--upgrade-software false --lang $mirror_language" ]]
                [[ "${mirror_call[*]:6}" == "--source $mirror_source" ]]
                [[ -n "$mirror_zh" && -n "$mirror_en" ]]
            done
        done
        OS=rocky
        func_system_mirrors <<< $'1\n1' >/dev/null
        [[ "${mirror_call[*]:6}" == '--source mirrors.aliyun.com --branch rockylinux' ]]
        OS=debian
        func_system_mirrors <<< $'8\nmirror.example.com\nlinux/debian' >/dev/null
        [[ "${mirror_call[*]:6}" == '--source mirror.example.com --branch linux/debian' ]]
        func_system_mirrors <<< $'8\nmirror.example.com\n\n' >/dev/null
        [[ "${mirror_call[*]:6}" == '--source mirror.example.com' ]]
        func_system_mirrors <<< $'invalid\n1\n99\n2' >/dev/null
        [[ "${mirror_call[*]:6}" == '--source mirrors.tencent.com' ]]
        func_system_mirrors <<< $'1\n0\n2\n1' >/dev/null
        [[ "${mirror_call[*]:6}" == '--source mirrors.xtom.hk' ]]
        for mirror_back in 0 q Q ''; do
            mirror_call=()
            func_system_mirrors <<<"$mirror_back" >/dev/null
            [[ ${#mirror_call[@]} == 0 ]]
        done
        mirror_call=()
        func_system_mirrors <<< $'8\n\n0' >/dev/null
        [[ ${#mirror_call[@]} == 0 ]]
        func_system_mirrors <<< $'1\nq\n0' >/dev/null
        [[ ${#mirror_call[@]} == 0 ]]
    done
    mirror_status=23
    if func_system_mirrors <<< $'1\n1' >/dev/null; then
        echo 'Mirror switch must preserve the remote script failure.' >&2
        exit 1
    else
        [[ $? == 23 ]]
    fi
)
(
    source src/system_reinstall.sh
    VPSO_LANGUAGE="zh"
    system_reinstall_set_target 1
    [[ "$SYSTEM_REINSTALL_LABEL" == "Debian 13" ]]
    [[ "${SYSTEM_REINSTALL_TARGET[*]}" == "debian 13" ]]
    system_reinstall_set_target 41
    [[ "$SYSTEM_REINSTALL_LABEL" == "Windows 11 Pro" ]]
    [[ "${SYSTEM_REINSTALL_TARGET[*]}" == "windows --image-name Windows 11 Pro --lang zh-cn" ]]
    system_reinstall_set_password "Passw0rd!"
    [[ "$SYSTEM_REINSTALL_AUTH_MODE" == "password" ]]
    [[ "${SYSTEM_REINSTALL_ACCESS_ARGS[*]}" == "--password Passw0rd!" ]]
    system_reinstall_set_ssh_port "２２２２"
    [[ "$SYSTEM_REINSTALL_SSH_PORT" == "2222" ]]
    system_reinstall_set_ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE2sjkXzvKPCdYfwtG2nOuQ4Vd8f0SmA0fMGVCpMtrLS test@example.com"
    [[ "$SYSTEM_REINSTALL_AUTH_MODE" == "ssh_key" ]]
    ! system_reinstall_is_valid_ssh_public_key "ssh-ed25519 not-base64 test@example.com"
    ! system_reinstall_set_ssh_port "65536"
    for reinstall_target in 2 3 4 11 12 13 14 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 42 44 45 46 47; do
        system_reinstall_set_target "$reinstall_target"
        [[ -n "$SYSTEM_REINSTALL_LABEL" && "${#SYSTEM_REINSTALL_TARGET[@]}" -gt 0 ]]
    done
    system_reinstall_set_windows7_target "https://example.com/windows7.iso"
    [[ "$SYSTEM_REINSTALL_LABEL" == "Windows 7 Ultimate" ]]
    [[ "${SYSTEM_REINSTALL_TARGET[*]}" == "windows --image-name Windows 7 Ultimate --lang zh-cn --iso https://example.com/windows7.iso" ]]
    if system_reinstall_set_windows7_target "file:///tmp/windows7.iso"; then
        echo "Windows 7 target must reject local ISO paths." >&2
        exit 1
    fi
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
(
    source src/compose_runtime.sh
    source src/subscription_apps.sh
    random_secret=$(generate_random_secret)
    [[ "$random_secret" =~ ^[0-9a-f]{64}$ ]]
    [[ "$(compose_yaml_quote 'pa$sw"ord\# value')" == '"pa$$sw\"ord\\# value"' ]]
    compose_secure_tmp=$(mktemp /tmp/vps-compose-secure.XXXXXX)
    chmod 644 "$compose_secure_tmp"
    compose_write_secure_file "$compose_secure_tmp" <<'EOF'
services: {}
EOF
    [[ "$(stat -c '%a' "$compose_secure_tmp")" == "600" ]]
    rm -f "$compose_secure_tmp"
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
        reload_applied_config_kind compose "$compose_apply_tmp/project/docker-compose.yml" <<< $'y\nYES\n'
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
(
    traffic_guard_reload_tmp=$(mktemp -d /tmp/vps-traffic-guard-reload-smoke.XXXXXX)
    traffic_guard_restore_ssh_only_firewall_from_config() {
        printf '%s\n' "$1" > "$traffic_guard_reload_tmp/restore-config"
    }
    confirm_risk_action() { return 1; }
    reload_applied_config_kind traffic-guard "$traffic_guard_reload_tmp/current.conf" "$traffic_guard_reload_tmp/previous.conf" >/dev/null
    grep -Fxq "$traffic_guard_reload_tmp/previous.conf" "$traffic_guard_reload_tmp/restore-config"
    rm -f "$traffic_guard_reload_tmp/restore-config"
    rmdir "$traffic_guard_reload_tmp"
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

(
    source src/common.sh
    source src/firewall.sh

    ss() {
        cat <<'SS_OUTPUT'
tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=100,fd=3))
udp UNCONN 0 0 [::]:53 [::]:* users:(("dnsd",pid=101,fd=4))
tcp LISTEN 0 128 127.0.0.1:8080 0.0.0.0:* users:(("local-app",pid=102,fd=5))
udp UNCONN 0 0 [::1]:5353 [::]:* users:(("mdns",pid=103,fd=6))
SS_OUTPUT
    }
    docker() {
        case "$1" in
            ps)
                printf '%s\n' web localdb
                ;;
            port)
                case "$2" in
                    web)
                        printf '%s\n' \
                            '80/tcp -> 0.0.0.0:8080' \
                            '80/tcp -> [::]:8080'
                        ;;
                    localdb)
                        printf '%s\n' '3306/tcp -> 127.0.0.1:3306'
                        ;;
                esac
                ;;
        esac
    }
    detected_rules=$(firewall_detect_public_listener_rules)
    grep -Fxq '22/tcp' <<<"$detected_rules"
    grep -Fxq '53/udp' <<<"$detected_rules"
    [[ "$(SSH_CONNECTION='198.51.100.10 54321 203.0.113.10 2222' firewall_detect_ssh_port)" == "2222" ]]
    if grep -Eq '8080|5353|22/udp|53/tcp' <<<"$detected_rules"; then
        echo "Firewall listener detection must preserve protocol and exclude loopback listeners." >&2
        exit 1
    fi
    firewall_plan=$(firewall_build_minimum_plan 22)
    grep -Fq '22|tcp|0.0.0.0|sshd|系统监听;SSH 保护|-|yes' <<<"$firewall_plan"
    grep -Fq '53|udp|[::]|dnsd|系统监听|-|no' <<<"$firewall_plan"
    grep -Fq '8080|tcp|0.0.0.0;[::]|docker:web|Docker|8080 -> 80/tcp|no' <<<"$firewall_plan"
    if grep -Eq '3306|local-app|mdns' <<<"$firewall_plan"; then
        echo "Firewall plan must exclude loopback system and Docker listeners." >&2
        exit 1
    fi
    selected_rules=$(firewall_select_minimum_plan_rules "$firewall_plan" "2,3")
    [[ "$selected_rules" == "22/tcp" ]]
    selected_rules=$(firewall_select_minimum_plan_rules "$firewall_plan" "1" 2>/dev/null)
    grep -Fxq '22/tcp' <<<"$selected_rules"
    selected_rules=$(firewall_select_minimum_plan_rules "$firewall_plan" "03")
    if grep -Fxq '8080/tcp' <<<"$selected_rules"; then
        echo "Firewall plan selection must accept zero-padded decimal indexes safely." >&2
        exit 1
    fi
    if firewall_select_minimum_plan_rules "$firewall_plan" "99" >/dev/null 2>&1; then
        echo "Firewall plan selection must reject out-of-range indexes." >&2
        exit 1
    fi

    OS=ubuntu
    firewall_calls=$(mktemp /tmp/vps-firewall-rule-smoke.XXXXXX)
    ufw() {
        printf '%s\n' "$*" >> "$firewall_calls"
        [[ "$*" != "allow 443/udp" ]]
    }
    firewall_apply_port_input add "80,8000-9000" tcp
    grep -Fxq 'allow 80/tcp' "$firewall_calls"
    grep -Fxq 'allow 8000:9000/tcp' "$firewall_calls"
    if grep -Fq '/udp' "$firewall_calls"; then
        echo "TCP-only firewall input must not add UDP rules." >&2
        exit 1
    fi
    if firewall_apply_port_input add "443" both >/dev/null 2>&1; then
        echo "Firewall rule application must report partial command failures." >&2
        exit 1
    fi
    : > "$firewall_calls"
    ufw() {
        printf '%s\n' "$*" >> "$firewall_calls"
        [[ "$*" == "delete allow 80" ]]
    }
    firewall_apply_port_input delete "80" both
    grep -Fxq 'delete allow 80' "$firewall_calls"
    if grep -Eq '/(tcp|udp)' "$firewall_calls"; then
        echo "Legacy protocol-agnostic UFW rules must be deleted without false per-protocol failures." >&2
        exit 1
    fi
    rm -f "$firewall_calls"
)

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
    source src/language.sh
    source src/firewall.sh

    is_valid_connlimit_value 4294967295
    ! is_valid_connlimit_value 4294967296
    ! is_valid_connlimit_value 999999999999999999999999

    MOCK_CONNLIMIT_STATE=$(mktemp /tmp/vps-connlimit-reconcile-smoke.XXXXXX)
    trap 'rm -f "$MOCK_CONNLIMIT_STATE" "$MOCK_CONNLIMIT_STATE.tmp"' EXIT
    printf '%s\n' "443|10" "443|10" "443|50" "8443|7" >"$MOCK_CONNLIMIT_STATE"
    mock_connlimit_iptables() {
        local action="$1"
        shift
        local port="" limit="" comment="" i rule rule_port rule_limit
        local -a args=("$@")

        if [[ "$action" == "-S" ]]; then
            while IFS= read -r rule; do
                IFS='|' read -r rule_port rule_limit <<<"$rule"
                printf '%s\n' "-A INPUT -p tcp --dport ${rule_port} --syn -m connlimit --connlimit-above ${rule_limit} --connlimit-mask 32 --connlimit-saddr -m comment --comment VPSO_CONN_LIMIT_PORT_${rule_port} -j REJECT --reject-with tcp-reset"
            done <"$MOCK_CONNLIMIT_STATE"
            return 0
        fi

        for ((i = 0; i < ${#args[@]}; i++)); do
            case "${args[$i]}" in
                --dport) port="${args[$((i + 1))]}" ;;
                --connlimit-above) limit="${args[$((i + 1))]}" ;;
                --comment) comment="${args[$((i + 1))]}" ;;
            esac
        done
        [[ "$comment" == "VPSO_CONN_LIMIT_PORT_${port}" ]] || return 1

        case "$action" in
            -C)
                grep -Fxq "${port}|${limit}" "$MOCK_CONNLIMIT_STATE"
                ;;
            -I)
                printf '%s\n' "${port}|${limit}" >>"$MOCK_CONNLIMIT_STATE"
                ;;
            -D)
                awk -v target="${port}|${limit}" '
                    !removed && $0 == target { removed = 1; next }
                    { print }
                    END { exit (removed ? 0 : 1) }
                ' "$MOCK_CONNLIMIT_STATE" >"$MOCK_CONNLIMIT_STATE.tmp" || return 1
                mv "$MOCK_CONNLIMIT_STATE.tmp" "$MOCK_CONNLIMIT_STATE"
                ;;
            *) return 1 ;;
        esac
    }

    [[ -z "$(port_connlimit_rule_limits_for_port mock_connlimit_iptables 44)" ]]
    run_port_connlimit_rule_action mock_connlimit_iptables add 443 50 32 IPv4 >/dev/null
    [[ "$(grep -xc '443|50' "$MOCK_CONNLIMIT_STATE")" -eq 1 ]]
    [[ "$(grep -c '^443|' "$MOCK_CONNLIMIT_STATE")" -eq 1 ]]
    [[ "$(grep -xc '8443|7' "$MOCK_CONNLIMIT_STATE")" -eq 1 ]]

    printf '%s\n' "443|50" "443|50" "8443|7" >"$MOCK_CONNLIMIT_STATE"
    run_port_connlimit_rule_action mock_connlimit_iptables delete 443 50 32 IPv4 >/dev/null
    [[ "$(grep -c '^443|' "$MOCK_CONNLIMIT_STATE" || true)" -eq 0 ]]
    [[ "$(grep -xc '8443|7' "$MOCK_CONNLIMIT_STATE")" -eq 1 ]]
)

(
    source src/common.sh
    source src/language.sh
    source src/validate.sh
    source src/firewall.sh

    PORT_CONNLIMIT_KERNEL_RELEASE=4.19.9
    ! port_connlimit_kernel_supports_ct_count
    PORT_CONNLIMIT_KERNEL_RELEASE=4.19.10
    port_connlimit_kernel_supports_ct_count
    PORT_CONNLIMIT_KERNEL_RELEASE=6.8.0-custom
    port_connlimit_kernel_supports_ct_count

    merged=$(printf '%s\n' '4|443|50' '4|443|10' '4|443|10' '6|8443|7' | port_connlimit_merge_rule_entries)
    [[ "$(grep -xc '4|443|10' <<<"$merged")" -eq 1 ]]
    [[ "$(grep -xc '6|8443|7' <<<"$merged")" -eq 1 ]]

    updated=$(port_connlimit_update_rule_entries "$merged" add 443 50 4 6 | port_connlimit_merge_rule_entries)
    [[ "$(grep -xc '4|443|50' <<<"$updated")" -eq 1 ]]
    [[ "$(grep -xc '6|443|50' <<<"$updated")" -eq 1 ]]
    [[ "$(grep -c '|443|10' <<<"$updated" || true)" -eq 0 ]]
    [[ "$(grep -xc '6|8443|7' <<<"$updated")" -eq 1 ]]

    rendered=$(render_port_connlimit_nft_config "$updated")
    grep -Fq 'flush table inet vps_optimize_connlimit' <<<"$rendered"
    grep -Fq 'set v4_p443 { type ipv4_addr; size 65535; flags dynamic; }' <<<"$rendered"
    grep -Fq 'set v6_p443 { type ipv6_addr; size 65535; flags dynamic; }' <<<"$rendered"
    grep -Fq 'add @v4_p443 { ip saddr ct count over 50 } reject with tcp reset comment "VPSO_CONN_LIMIT_PORT_443"' <<<"$rendered"
    grep -Fq 'add @v6_p443 { ip6 saddr ct count over 50 } reject with tcp reset comment "VPSO_CONN_LIMIT_PORT_443"' <<<"$rendered"

    nft() {
        if [[ "$1" == "-nn" && "$2" == "list" ]]; then
            cat <<'NFT_RULES'
table inet vps_optimize_connlimit {
    chain input {
        tcp dport 443 ct state new add @v4_p443 { ip saddr ct count over 50 } reject with tcp reset comment "VPSO_CONN_LIMIT_PORT_443"
        tcp dport 8443 ct state new add @v6_p8443 { ip6 saddr ct count over 7 } reject with tcp reset comment "VPSO_CONN_LIMIT_PORT_8443"
    }
}
NFT_RULES
            return 0
        fi
        if [[ "$1" == "-c" && "$2" == "-f" && "$3" == "-" ]]; then
            probe=$(cat)
            grep -Fq 'ct count over 1' <<<"$probe"
            return $?
        fi
        return 1
    }
    parsed=$(port_connlimit_nft_rule_entries)
    grep -Fxq '4|443|50' <<<"$parsed"
    grep -Fxq '6|8443|7' <<<"$parsed"
    port_connlimit_nft_supported
    port_connlimit_nft_supported() { return 1; }
    ! ensure_nft_connlimit_support >/dev/null

    port_connlimit_nft_rule_entries() {
        printf '%s\n' '4|443|10' '6|8443|7'
    }
    port_connlimit_legacy_rule_entries() {
        printf '%s\n' '4|443|5' '4|9443|9' '4|9443|9'
    }
    nft_write_calls=0
    nft_written_entries=""
    write_port_connlimit_nft_config() {
        nft_write_calls=$((nft_write_calls + 1))
        nft_written_entries="$1"
        [[ "$2" -eq 1 ]]
    }
    cleanup_calls=0
    cleaned_legacy=""
    cleanup_port_connlimit_legacy_rules() {
        cleanup_calls=$((cleanup_calls + 1))
        cleaned_legacy="$1"
    }

    run_nft_port_connlimit_action add 443 50 1 >/dev/null
    [[ "$nft_write_calls" -eq 1 ]]
    [[ "$cleanup_calls" -eq 1 ]]
    [[ "$(grep -xc '4|443|50' <<<"$nft_written_entries")" -eq 1 ]]
    [[ "$(grep -xc '6|443|50' <<<"$nft_written_entries")" -eq 1 ]]
    [[ "$(grep -xc '4|9443|9' <<<"$nft_written_entries")" -eq 1 ]]
    [[ "$(grep -xc '4|443|5' <<<"$nft_written_entries" || true)" -eq 0 ]]
    [[ "$(grep -xc '4|9443|9' <<<"$cleaned_legacy")" -eq 2 ]]

    port_connlimit_nft_rule_entries() {
        printf '%s\n' '4|443|50' '6|443|50'
    }
    port_connlimit_legacy_rule_entries() { :; }
    nft_write_calls=0
    nft_apply_mode=-1
    write_port_connlimit_nft_config() {
        nft_write_calls=$((nft_write_calls + 1))
        nft_apply_mode="$2"
    }
    run_nft_port_connlimit_action add 443 50 1 >/dev/null
    [[ "$nft_write_calls" -eq 1 ]]
    [[ "$nft_apply_mode" -eq 0 ]]

    service=$(render_nft_port_connlimit_service /usr/sbin/nft)
    grep -Fq 'ExecStartPre=-/usr/sbin/nft add table inet vps_optimize_connlimit' <<<"$service"
    grep -Fq 'ExecStart=/usr/sbin/nft -f /etc/vps-optimize/port-connlimit.nft' <<<"$service"
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

(
    source src/common.sh
    source src/ui.sh
    source src/validate.sh
    source src/tcp_peek_engine.sh
    source src/sni_stack_config.sh

    ENTRY_MODE=nginx-stream
    NGINX_LISTEN_ADDR=0.0.0.0
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
    REALITY_SNI=reality.example.com
    SITE_DOMAINS=()
    SITE_BACKEND_ADDRS=()
    SITE_BACKEND_PORTS=()
    TCP_ROUTE_SNIS=()
    TCP_ROUTE_ADDRS=()
    TCP_ROUTE_PORTS=()
    XRAY_SNI_ROUTE_SNIS=()
    XRAY_SNI_ROUTE_ADDRS=()
    XRAY_SNI_ROUTE_PORTS=()
    SNI_IP_WHITELIST_DOMAINS=()
    SNI_IP_WHITELIST_RANGES=()

    WEB_PROXY_ENGINE=nginx
    current_summary_nginx=$(print_sni_stack_current_summary 2>&1)
    grep -Fq 'Web 反代：  Nginx 本地 HTTPS 反代 (127.0.0.1:8443)' <<<"$current_summary_nginx"
    grep -Fq '公网入口：  0.0.0.0:443 -> Nginx 本地 HTTPS 反代 127.0.0.1:8443' <<<"$current_summary_nginx"
    grep -Fq 'Nginx Web /etc/nginx/conf.d/vps_sni_web_8443.conf' <<<"$current_summary_nginx"
    grep -Fq 'Nginx 本地 HTTPS 反代：' <<<"$current_summary_nginx"
    ! grep -Fq 'Caddy /etc/caddy/conf.d/panel.example.com.caddy' <<<"$current_summary_nginx"
    ! grep -Fq 'Caddy 本地：' <<<"$current_summary_nginx"

    WEB_PROXY_ENGINE=caddy
    current_summary_caddy=$(print_sni_stack_current_summary 2>&1)
    grep -Fq 'Web 反代：  Caddy 本地 HTTPS 反代 (127.0.0.1:8443)' <<<"$current_summary_caddy"
    grep -Fq '公网入口：  0.0.0.0:443 -> Caddy 本地 HTTPS 反代 127.0.0.1:8443' <<<"$current_summary_caddy"
    grep -Fq 'Caddy /etc/caddy/conf.d/panel.example.com.caddy' <<<"$current_summary_caddy"
    grep -Fq 'Caddy 本地 HTTPS 反代：' <<<"$current_summary_caddy"
    ! grep -Fq 'Nginx Web /etc/nginx/conf.d/vps_sni_web_8443.conf' <<<"$current_summary_caddy"

    web_proxy_engine_supports_web_whitelist nginx-stream caddy
    web_proxy_engine_supports_web_whitelist nginx-stream nginx
    web_proxy_engine_supports_web_whitelist tcp-peek caddy
    web_proxy_engine_supports_web_whitelist tcp-peek nginx
    ! web_proxy_engine_supports_web_whitelist xray-fallback caddy
    ! web_proxy_engine_supports_web_whitelist xray-fallback nginx
)

[[ "$(nginx_stream_listen_directives "127.0.0.1" "443")" == "    listen 127.0.0.1:443;" ]]
[[ "$(nginx_stream_listen_directives "0.0.0.0" "443" | grep -c '^    listen ')" == "2" ]]
[[ "$(nginx_stream_listen_directives "::1" "443")" == "    listen [::1]:443;" ]]
[[ "$(xui_cert_setting_key_sql_list)" == *"subcertfile"* ]]

if command -v python3 >/dev/null 2>&1; then
    (
        source src/common.sh
        source src/sni_stack_profiles.sh
        xui_uses_postgresql() { return 1; }
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
        grep -Fxq 'subDomain=' <<<"$xui_domain_values"
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
    source src/input.sh
    source src/validate.sh
    source src/caddy_certificates.sh
    source src/sni_stack_config.sh
    source src/caddy_proxy.sh
    caddy_proxy_tmp=$(mktemp /tmp/vps-caddy-proxy.XXXXXX)
    caddy_single_entry_tmp=$(mktemp /tmp/vps-caddy-single-entry.XXXXXX)
    nginx_proxy_tmp=$(mktemp /tmp/vps-nginx-proxy.XXXXXX)
    is_valid_backend_addr "backend.internal"
    is_valid_backend_addr "dockge"
    ! is_valid_backend_addr "bad/backend"
    write_caddy_reverse_proxy_conf "docker.example.com" "backend.internal" "8080" "n" "$caddy_proxy_tmp"
    grep -q 'reverse_proxy backend.internal:8080' "$caddy_proxy_tmp"
    [[ "$(caddy_conf_first_reverse_proxy_target "$caddy_proxy_tmp")" == "backend.internal:8080" ]]
    [[ "$(caddy_reverse_proxy_target_port "$(caddy_conf_first_reverse_proxy_target "$caddy_proxy_tmp")")" == "8080" ]]
    [[ "$(caddy_reverse_proxy_target_host "$(caddy_conf_first_reverse_proxy_target "$caddy_proxy_tmp")")" == "backend.internal" ]]
    [[ "$(caddy_reverse_proxy_target_host "https://[::1]:8443")" == "::1" ]]
    write_caddy_reverse_proxy_conf "view.stardustcloud.best" "127.0.0.1" "25774" "n" "$caddy_proxy_tmp"
    grep -q '^view.stardustcloud.best {$' "$caddy_proxy_tmp"
    grep -q 'reverse_proxy 127.0.0.1:25774' "$caddy_proxy_tmp"
    write_caddy_reverse_proxy_conf "docker.example.com" "backend.local" "8443" "y" "$caddy_proxy_tmp"
    grep -q 'reverse_proxy https://backend.local:8443' "$caddy_proxy_tmp"
    [[ "$(caddy_conf_first_reverse_proxy_target "$caddy_proxy_tmp")" == "https://backend.local:8443" ]]
    [[ "$(caddy_reverse_proxy_target_port "$(caddy_conf_first_reverse_proxy_target "$caddy_proxy_tmp")")" == "8443" ]]
    grep -q 'tls_insecure_skip_verify' "$caddy_proxy_tmp"
    cat > "$caddy_single_entry_tmp" <<'EOF'
https://docker.example.com:9443 {
    bind 127.0.0.1
    tls /etc/caddy/certs/docker.example.com.crt /etc/caddy/certs/docker.example.com.key
    reverse_proxy backend.internal:8080
}
EOF
    [[ "$(caddy_conf_site_listen_port "$caddy_single_entry_tmp")" == "9443" ]]
    [[ "$(caddy_conf_site_listen_target "$caddy_single_entry_tmp")" == "127.0.0.1:9443" ]]
    [[ "$(caddy_conf_first_reverse_proxy_target "$caddy_single_entry_tmp")" == "backend.internal:8080" ]]
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
    rm -f "$caddy_proxy_tmp"
    rm -f "$caddy_single_entry_tmp"
    rm -f "$nginx_proxy_tmp"
)

(
    CYAN='' GREEN='' YELLOW='' RED='' BLUE='' PLAIN=''
    source src/input.sh
    source src/validate.sh
    backend_addr_resolution_status() { return 0; }
    tcp_target_reachable() { [[ "$1" == "reachable.internal" && "$2" == "8080" ]]; }
    reachable_output=$(probe_backend_target "测试后端" "reachable.internal" "8080")
    grep -Fq 'reachable.internal:8080 可连接' <<<"$reachable_output"
    if probe_backend_target "测试后端" "unreachable.internal" "8080" >/dev/null; then
        echo "Backend probe must fail when the exact target is unreachable." >&2
        exit 1
    fi
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
    SITE_BACKEND_ADDRS=(127.0.0.1 backend.internal)
    SITE_BACKEND_PORTS=(3000 5000)
    nginx() { printf '%s\n' 'nginx version: nginx/1.24.0' >&2; }
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
    grep -Fq 'proxy_pass http://backend.internal:5000;' "$nginx_sni_web_tmp"
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

    printf '%s\n' "engine='unknown'" > "$(single_443_engine_state_path)"
    [[ "$(single_443_current_engine)" == "invalid:unknown" ]]
    rm "$(single_443_engine_state_path)"
    printf '%s\n' "ENTRY_MODE='unknown'" > "$(sni_stack_env_path)"
    [[ "$(single_443_current_engine)" == "invalid:unknown" ]]
    printf '%s\n' '# legacy configuration without ENTRY_MODE' > "$(sni_stack_env_path)"
    [[ "$(single_443_current_engine)" == "nginx-stream" ]]
    rm "$(sni_stack_env_path)"
    [[ "$(single_443_current_engine)" == "not-configured" ]]

    select_initial_entry_mode >/dev/null 2>&1 <<< $'3\n'
    [[ "$ENTRY_MODE" == "tcp-peek" ]]

    rm -f "$(single_443_engine_state_path)"
    rm -f "$(sni_stack_env_path)"
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
    grep -Fq '最新版 3.x 安装器询问 SSL 时选第 4 项 Skip SSL；再选 y 仅绑定 127.0.0.1。' "$panel_output"

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
[[ "$(is_trusted_remote_script_url "https://raw.githubusercontent.com/Sagit-chu/flvx/main/panel_install.sh")" == *"项目内置硬编码外部脚本源"* ]]
[[ "$(is_trusted_remote_script_url "https://raw.githubusercontent.com/EasyTier/EasyTier/main/script/install.sh")" == *"EasyTier 官方"* ]]
[[ "$(is_trusted_remote_script_url "https://tailscale.com/install.sh")" == *"Tailscale 官方"* ]]
[[ "$(is_trusted_remote_script_url "https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh")" == *"项目内置硬编码外部脚本源"* ]]
[[ "$(is_trusted_remote_script_url "https://github.com/arloor/nftables-nat-rust/releases/download/v2.0.0/setup.sh")" == *"项目内置硬编码外部脚本源"* ]]
if is_trusted_remote_script_url "https://example.com/not-built-in.sh" >/dev/null; then
    echo "Unexpected trusted remote script URL." >&2
    exit 1
fi
remote_output=$(run_remote_script "smoke remote script" "file://$remote_script" 2>&1)
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
dog_confirm=""
read_trimmed dog_confirm "确认操作？[y/N]: " <<< ""
[[ -z "$dog_confirm" ]]
[[ "$(normalize_menu_choice_input " add ")" == "add" ]]
[[ "$(normalize_menu_choice_input "tg")" == "tg" ]]
[[ "$(normalize_menu_choice_input "q")" == "0" ]]
[[ "$(normalize_menu_choice_input "lang")" == "lang" ]]
UI_LANGUAGE=en
[[ "$(ui_text "中文" "English" "Русский")" == "English" ]]
UI_LANGUAGE=ru
[[ "$(ui_text "中文" "English" "Русский")" == "Русский" ]]
UI_LANGUAGE=zh
[[ "$(format_bytes "")" == "0B" ]]
[[ "$(format_bytes 1023)" == "1023B" ]]
telegram_notification_due 1h 9 13
telegram_notification_due 6h 9 12
telegram_notification_due 12h 9 0
telegram_notification_due daily 9 9
if telegram_notification_due 6h 9 13 || telegram_notification_due daily 9 8 || telegram_notification_due invalid 9 9; then
    echo "Unexpected dog Telegram notification schedule match." >&2
    exit 1
fi
if command -v jq >/dev/null 2>&1; then
    dog_notification_template=$(render_notification_template '<b>{server_name}</b>|{report}|{time}' 'node-a' 'port 443: 1GB' '2026-08-09 12:00:00')
    [[ "$dog_notification_template" == '<b>node-a</b>|port 443: 1GB|2026-08-09 12:00:00' ]]
    dog_nft_snapshot=$(printf '%s' '{"nftables":[{"counter":{"name":"port_443_in","bytes":123}},{"counter":{"name":"port_443_out","bytes":456}}]}' | parse_nft_counter_snapshot)
    [[ "$(jq -r '.port_443_in + .port_443_out' <<< "$dog_nft_snapshot")" == "579" ]]
else
    echo "jq not found; skipped dog notification rendering and nft JSON snapshot tests."
fi
bash tests/dog-limits.sh


(
    NGINX_LISTEN_PORT=443
    systemctl_calls=$(mktemp /tmp/vpso-mux-systemctl-smoke.XXXXXX)
    trap 'rm -f "$systemctl_calls"' EXIT
    source src/tcp_peek_engine.sh
    detect_443_listener() { printf '%s\n' 'unknown|none'; }
    listener_info_has_entry() { return 1; }
    print_vpso_mux_failure_context() { return 1; }
    write_vpso_mux_systemd_service() { return 0; }
    systemctl() {
        printf '%s\n' "$*" >> "$systemctl_calls"
        case "$1" in
            cat) return 0 ;;
            is-active|is-enabled) return 1 ;;
            *) return 0 ;;
        esac
    }
    stop_vpso_mux_service_if_public_443 >/dev/null
    grep -Fq 'disable --now vpso-mux' "$systemctl_calls"
)


(
    update_tmp=$(mktemp -d /tmp/vps-update-smoke.XXXXXX)
    cp dist/vps.sh "$update_tmp/local.sh"
    cp dist/vps.sh "$update_tmp/remote.sh"
    printf '\n# same-version content update\n' >> "$update_tmp/remote.sh"
    sha256sum "$update_tmp/remote.sh" > "$update_tmp/remote.sh.sha256"

    source src/updater.sh
    UPDATE_MIRROR_CONFIG="${update_tmp}/mirror.conf"
    SCRIPT_UPDATE_CACHE="${update_tmp}/update.cache"
    clear() { :; }
    print_breadcrumb() { :; }
    pause_after_external_script() { :; }
    sleep() { :; }
    load_script_update_mirror
    [[ "$UPDATE_URL" == https://ghfast.top/https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh ]]
    [[ "$UPDATE_SHA256_URL" == "${UPDATE_URL}.sha256" ]]
    for VPSO_LANGUAGE in zh en ru; do
        touch "$SCRIPT_UPDATE_CACHE"
        func_configure_update_mirror <<< $'http://mirror.example\nhttps://mirror.example/' >/dev/null
        [[ "$(cat "$UPDATE_MIRROR_CONFIG")" == https://mirror.example ]]
        [[ ! -f "$SCRIPT_UPDATE_CACHE" ]]
        UPDATE_MIRROR=https://ghfast.top
        load_script_update_mirror
        [[ "$UPDATE_URL" == https://mirror.example/https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh ]]
        [[ "$UPDATE_SHA256_URL" == "${UPDATE_URL}.sha256" ]]
        for mirror_back in q Q ''; do
            func_configure_update_mirror <<<"$mirror_back" >/dev/null
            [[ "$(cat "$UPDATE_MIRROR_CONFIG")" == https://mirror.example ]]
        done
    done
    curl() {
        local url="${!#}"
        case "$url" in
            "$UPDATE_URL") cat "$update_tmp/remote.sh" ;;
            "$UPDATE_SHA256_URL") cat "$update_tmp/remote.sh.sha256" ;;
            *) return 1 ;;
        esac
    }
    [[ "$(fetch_latest_script_version)" == "$vps_smoke_script_version" ]]
    [[ "$(fetch_latest_script_sha256)" == "$(sha256sum "$update_tmp/remote.sh" | awk '{print $1}')" ]]
    (
        download_remote_script() {
            case "$1" in
                "$UPDATE_URL") cp "$update_tmp/remote.sh" "$2" ;;
                "$UPDATE_SHA256_URL") cp "$update_tmp/remote.sh.sha256" "$2" ;;
                *) return 1 ;;
            esac
        }
        download_verified_update_script "$update_tmp/verified.sh"
        cmp "$update_tmp/remote.sh" "$update_tmp/verified.sh"
        printf '%064d  remote.sh\n' 0 > "$update_tmp/remote.sh.sha256"
        if download_verified_update_script "$update_tmp/rejected.sh"; then
            echo 'A mirrored update with a checksum mismatch must be rejected.' >&2
            exit 1
        fi
        [[ ! -e "$update_tmp/rejected.sh" ]]
    )
    sha256sum "$update_tmp/remote.sh" > "$update_tmp/remote.sh.sha256"
    UPDATE_URL="file://${update_tmp}/remote.sh"
    UPDATE_SHA256_URL="${UPDATE_URL}.sha256"
    SCRIPT_UPDATE_CACHE="${update_tmp}/update.cache"
    VPSO_CURRENT_SCRIPT_PATH="${update_tmp}/local.sh"
    curl() {
        local url="${!#}"
        cat "${url#file://}"
    }

    update_status=$(check_script_update_status force)
    if [[ "$update_status" != "available|${vps_smoke_script_version}" ]]; then
        echo "Same-version content drift must report available; got: ${update_status}" >&2
        exit 1
    fi
    cp "$update_tmp/remote.sh" "$update_tmp/local.sh"
    update_status=$(check_script_update_status force)
    if [[ "$update_status" != "current|${vps_smoke_script_version}" ]]; then
        echo "Matching local and remote script hashes must report current; got: ${update_status}" >&2
        exit 1
    fi

    if run_remote_script "HTTP smoke" "http://example.invalid/script.sh" >/dev/null 2>&1; then
        echo "Remote script runner must reject non-HTTPS sources." >&2
        exit 1
    fi
    rm -f "$update_tmp/local.sh" "$update_tmp/remote.sh" "$update_tmp/remote.sh.sha256" "$update_tmp/update.cache" "$update_tmp/mirror.conf" "$update_tmp/verified.sh"
    rmdir "$update_tmp"
)

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
        confirm_standard_action() { return 0; }
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
    source src/traffic_guard.sh
    local offsets usage_rx usage_tx usage
    local tmp fake_sys fake_proc fake_bin fake_calls fake_firewall_calls fake_firewall_rules guard config state_dir log_file iface current_cycle detected_port insert_count

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
    cat > "${fake_bin}/ss" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' \
    'LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=1,fd=3))' \
    'LISTEN 0 128 [::]:2222 [::]:* users:(("sshd",pid=1,fd=4))'
EOF
    chmod +x "${fake_bin}/ss"
    detected_port=$(SSH_CONNECTION='198.51.100.10 50000 203.0.113.10 2222' PATH="${fake_bin}:$PATH" traffic_guard_detect_ssh_port)
    if [[ "$detected_port" != "2222" ]]; then
        echo "Traffic guard must preserve the SSH port used by the current connection; got ${detected_port:-unset}." >&2
        exit 1
    fi
    if SSH_CONNECTION='' PATH="${fake_bin}:$PATH" traffic_guard_detect_ssh_port >/dev/null; then
        echo "Traffic guard must reject ambiguous SSH listeners without a current SSH connection." >&2
        exit 1
    fi
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
        local action="${1:-log}" limit_bytes="${2:-1000000000}" initial_bytes="${3:-0}" ssh_port="${4:-}"
        cat > "$config" <<EOF
ENABLED='1'
IFACE='${iface}'
MODE='tx'
LIMIT_GB='1'
LIMIT_BYTES='${limit_bytes}'
CYCLE_DAY='1'
WARN_PERCENT='90'
ACTION='${action}'
SSH_PORT='${ssh_port}'
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
    source "${state_dir}/state"
    if [[ "${LAST_USAGE:-}" != "2000" || "${TRIPPED:-}" != "0" ]]; then
        echo "Traffic guard poweroff failure must keep retry state honest; usage=${LAST_USAGE:-unset} tripped=${TRIPPED:-unset}." >&2
        exit 1
    fi
    grep -q 'poweroff command failed; will retry on next timer run' "$log_file"
    grep -q '^systemctl poweroff$' "$fake_calls"
    grep -q '^poweroff $' "$fake_calls"
    grep -q '^shutdown -h now$' "$fake_calls"

    fake_firewall_calls="${tmp}/firewall-calls.log"
    fake_firewall_rules="${tmp}/firewall-rules"
    for cmd in iptables ip6tables; do
        cat > "${fake_bin}/${cmd}" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "\${0##*/}" "\$*" >> "${fake_firewall_calls}"
family="\${0##*/}"
case "\${1:-}" in
    -C)
        shift
        grep -Fxq -- "\${family} \$*" "${fake_firewall_rules}" 2>/dev/null
        ;;
    -I)
        chain="\$2"
        shift 3
        rule="\${family} \${chain} \$*"
        grep -Fxq -- "\$rule" "${fake_firewall_rules}" 2>/dev/null || printf '%s\n' "\$rule" >> "${fake_firewall_rules}"
        ;;
    -D)
        shift
        rule="\${family} \$*"
        grep -Fvx -- "\$rule" "${fake_firewall_rules}" 2>/dev/null > "${fake_firewall_rules}.tmp" || true
        mv -f "${fake_firewall_rules}.tmp" "${fake_firewall_rules}"
        ;;
    *) exit 1 ;;
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
    traffic_guard_write_smoke_config ssh-only 1000 0 2222
    PATH="${fake_bin}:$PATH" traffic_guard_run_smoke_checker
    source "${state_dir}/state"
    if [[ "${LAST_USAGE:-}" != "2000" || "${TRIPPED:-}" != "1" ]]; then
        echo "Traffic guard ssh-only success must persist the tripped state; usage=${LAST_USAGE:-unset} tripped=${TRIPPED:-unset}." >&2
        exit 1
    fi
    grep -Fq 'iptables -I INPUT 1 -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j DROP' "$fake_firewall_calls"
    grep -Fq 'iptables -I OUTPUT 1 -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j DROP' "$fake_firewall_calls"
    grep -Fq 'iptables -I FORWARD 1 -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j DROP' "$fake_firewall_calls"
    grep -Fq 'iptables -I INPUT 1 -i lo -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j ACCEPT' "$fake_firewall_calls"
    grep -Fq 'iptables -I OUTPUT 1 -o lo -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j ACCEPT' "$fake_firewall_calls"
    grep -Fq 'iptables -I INPUT 1 -p udp --sport 67 --dport 68 -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j ACCEPT' "$fake_firewall_calls"
    grep -Fq 'iptables -I OUTPUT 1 -p udp --sport 68 --dport 67 -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j ACCEPT' "$fake_firewall_calls"
    grep -Fq 'iptables -I INPUT 1 -p tcp --dport 2222 -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j ACCEPT' "$fake_firewall_calls"
    grep -Fq 'iptables -I OUTPUT 1 -p tcp --sport 2222 -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j ACCEPT' "$fake_firewall_calls"
    if [[ -s /proc/net/if_inet6 ]]; then
        grep -Fq 'ip6tables -I FORWARD 1 -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j DROP' "$fake_firewall_calls"
        grep -Fq 'ip6tables -I INPUT 1 -p udp --sport 547 --dport 546 -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j ACCEPT' "$fake_firewall_calls"
        grep -Fq 'ip6tables -I OUTPUT 1 -p udp --sport 546 --dport 547 -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j ACCEPT' "$fake_firewall_calls"
        for icmp_type in 1 2 3 4 130 131 132 133 134 135 136 137 141 142 143; do
            grep -Fq "ip6tables -I INPUT 1 -p ipv6-icmp --icmpv6-type ${icmp_type} -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j ACCEPT" "$fake_firewall_calls"
            grep -Fq "ip6tables -I OUTPUT 1 -p ipv6-icmp --icmpv6-type ${icmp_type} -m comment --comment VPSO-TRAFFIC-GUARD-SSH-ONLY -j ACCEPT" "$fake_firewall_calls"
        done
    fi
    grep -q 'ssh-only firewall enabled on TCP port 2222' "$log_file"
    if grep -q ' -D ' "$fake_firewall_calls"; then
        echo "Traffic guard apply must not delete active ssh-only firewall rules before ensuring them." >&2
        exit 1
    fi
    insert_count=$(grep -c ' -I ' "$fake_firewall_calls")
    PATH="${fake_bin}:$PATH" traffic_guard_run_smoke_checker
    if [[ "$(grep -c ' -I ' "$fake_firewall_calls")" != "$insert_count" ]] || grep -q ' -D ' "$fake_firewall_calls"; then
        echo "Traffic guard repeated apply must keep managed firewall rules idempotent." >&2
        exit 1
    fi
    TRAFFIC_GUARD_CHECKER="$guard" \
    TRAFFIC_GUARD_STATE_DIR="$state_dir" \
    TRAFFIC_GUARD_LOG="$log_file" \
    PATH="${fake_bin}:$PATH" \
        traffic_guard_restore_ssh_only_firewall_from_config "$config"
    if [[ -s "$fake_firewall_rules" ]]; then
        echo "Traffic guard restore must remove every managed ssh-only firewall rule." >&2
        cat "$fake_firewall_rules" >&2
        exit 1
    fi
}
traffic_guard_accounting_regression

(
    source src/backup.sh
    [[ "$(backup_resolve_custom_directory "$repo_root")" == "$repo_root" ]]
    [[ "$(backup_resolve_custom_directory /etc)" == "/etc" ]]
    ! backup_resolve_custom_directory /tmp
    backup_test_dir=$(mktemp -d /tmp/vpso-backup-smoke.XXXXXX)
    mkdir "$backup_test_dir/source"
    printf '%s\n' 'encrypted-backup-ok' > "$backup_test_dir/source/value.txt"
    [[ "$(backup_path_size_bytes "$backup_test_dir/source")" =~ ^[0-9]+$ ]]
    cleanup_test_dir=$(mktemp -d /tmp/vps_backup_smoke.XXXXXX)
    printf '%s\n' 'temporary-plaintext' > "$cleanup_test_dir/value.txt"
    backup_cleanup_temp_dir "$cleanup_test_dir"
    [[ ! -e "$cleanup_test_dir" ]]
    if command -v openssl >/dev/null 2>&1; then
        backup_create_archive "$backup_test_dir/source" "$backup_test_dir/test.tar.gz.enc" 'smoke-password-123'
        backup_archive_is_encrypted "$backup_test_dir/test.tar.gz.enc"
        backup_decrypt_archive "$backup_test_dir/test.tar.gz.enc" "$backup_test_dir/test.tar.gz" 'smoke-password-123'
        [[ "$(tar -xOzf "$backup_test_dir/test.tar.gz" ./value.txt)" == "encrypted-backup-ok" ]]
        rm -f "$backup_test_dir/test.tar.gz.enc" "$backup_test_dir/test.tar.gz"
    fi
    rm -f "$backup_test_dir/source/value.txt"
    rmdir "$backup_test_dir/source" "$backup_test_dir"
)
reality_guard_smoke_tmp=$(mktemp -d /tmp/vps-reality-guard-smoke.XXXXXX)
reality_guard_smoke_db="$reality_guard_smoke_tmp/x-ui.db"
source src/reality_guard.sh
python3 - "$reality_guard_smoke_db" <<'PY'
import json
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("create table inbounds (id integer primary key, port integer, remark text, stream_settings text)")
stream = {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
        "target": "cdn.example.com:443",
        "serverNames": ["cdn.example.com", "cdn-alt.example.com"],
        "privateKey": "keep-private-key",
        "shortIds": ["aabbccdd"],
    },
}
conn.execute("insert into inbounds values (1, 1443, 'reality-test', ?)", (json.dumps(stream),))
conn.commit()
PY
grep -Fq $'1\t1443\treality-test\tcdn.example.com,cdn-alt.example.com\tdisabled' < <(reality_guard_python list "$reality_guard_smoke_db")
reality_guard_python apply "$reality_guard_smoke_db" 1 100 10 20 200 30 40
python3 - "$reality_guard_smoke_db" <<'PY'
import json
import sqlite3
import sys

stream = json.loads(sqlite3.connect(sys.argv[1]).execute("select stream_settings from inbounds where id=1").fetchone()[0])
reality = stream["realitySettings"]
assert reality["privateKey"] == "keep-private-key"
assert reality["shortIds"] == ["aabbccdd"]
assert reality["limitFallbackUpload"] == {"afterBytes": 100, "bytesPerSec": 10, "burstBytesPerSec": 20}
assert reality["limitFallbackDownload"] == {"afterBytes": 200, "bytesPerSec": 30, "burstBytesPerSec": 40}
assert set(stream) == {"network", "security", "realitySettings"}
PY
reality_guard_python clear "$reality_guard_smoke_db" 1
python3 - "$reality_guard_smoke_db" <<'PY'
import json
import sqlite3
import sys

reality = json.loads(sqlite3.connect(sys.argv[1]).execute("select stream_settings from inbounds where id=1").fetchone()[0])["realitySettings"]
assert "limitFallbackUpload" not in reality
assert "limitFallbackDownload" not in reality
assert reality["privateKey"] == "keep-private-key"
PY

(
    XRAY_LISTEN_PORT=1443
    REALITY_SNI=cdn.example.com
    PANEL_DOMAIN=panel.example.com
    SITE_DOMAINS=()
    TCP_ROUTE_SNIS=()
    XRAY_SNI_ROUTE_SNIS=()
    XRAY_SNI_ROUTE_PORTS=()
    [[ "$(unregistered_reality_server_names "$reality_guard_smoke_db")" == "cdn-alt.example.com" ]]
    find_xui_database_candidates() { printf '%s\n' "$reality_guard_smoke_db"; }
    if validate_strict_sni_gate_reality_server_names >/dev/null; then
        echo "Strict SNI gate validation must reject an unregistered REALITY serverName." >&2
        exit 1
    fi
    XRAY_SNI_ROUTE_SNIS=(cdn-alt.example.com)
    XRAY_SNI_ROUTE_PORTS=(1443)
    [[ -z "$(unregistered_reality_server_names "$reality_guard_smoke_db")" ]]
    validate_strict_sni_gate_reality_server_names >/dev/null
)

(
    strict_gate_tmp=$(mktemp)
    trap 'rm -f "$strict_gate_tmp"' EXIT
    NGINX_LISTEN_PORT=443
    systemctl() { [[ "$1" == "is-active" && "$3" == "nginx" ]]; }
    printf '%s\n' '    default vps_ip_reject_backend;' > "$strict_gate_tmp"
    strict_sni_gate_runtime_active nginx-stream "$strict_gate_tmp"
    printf '%s\n' '    default xray_backend;' > "$strict_gate_tmp"
    if strict_sni_gate_runtime_active nginx-stream "$strict_gate_tmp"; then
        echo "Strict SNI runtime detection must reject a non-blocking Nginx default route." >&2
        exit 1
    fi
    systemctl() { [[ "$1" == "is-active" && "$3" == "vpso-mux" ]]; }
    printf '%s\n' 'reject_unknown_sni: true' > "$strict_gate_tmp"
    strict_sni_gate_runtime_active tcp-peek "$strict_gate_tmp"
)

(
    STRICT_SNI_GATE=false
    sync_calls=0
    saved_states=""
    load_sni_stack_env() { ENTRY_MODE="nginx-stream"; return 0; }
    get_entry_mode() { printf '%s' 'nginx-stream'; }
    confirm_danger() { return 0; }
    confirm_standard_action() { return 0; }
    validate_strict_sni_gate_reality_server_names() { return 0; }
    save_sni_stack_env() { saved_states+="${STRICT_SNI_GATE} "; }
    sync_strict_sni_gate_to_current_entry() {
        sync_calls=$((sync_calls + 1))
        [[ "$sync_calls" -gt 1 ]]
    }
    if set_strict_sni_gate true >/dev/null; then
        echo "Strict SNI gate transition must fail when the new state cannot be synchronized." >&2
        exit 1
    fi
    [[ "$STRICT_SNI_GATE" == "false" ]]
    [[ "$saved_states" == "true false " ]]
    [[ "$sync_calls" == "2" ]]
)

(
    clear() { :; }
    load_sni_stack_env() { ENTRY_MODE="nginx-stream"; return 0; }
    xui_uses_postgresql() { return 0; }
    print_strict_sni_gate_summary() { :; }
    read_trimmed() { printf -v "$1" '%s' '0'; }
    postgresql_menu_output=$(manage_reality_traffic_guard)
    [[ "$postgresql_menu_output" == *"不可用：仅支持本机 SQLite"* ]]
)

source src/xray_sni_routes.sh
(
    confirm_risk_action() { return 0; }
    sync_xray_sni_routes_to_entry_mode() { printf '%s\n' 'XRAY_ROUTES_SYNCED'; }
    sync_output=$(offer_sync_xray_sni_routes)
    [[ "$sync_output" == *"XRAY_ROUTES_SYNCED"* ]]
)
rm -f "$reality_guard_smoke_db"
rmdir "$reality_guard_smoke_tmp"

(
    source src/tcp_peek_engine.sh
    STRICT_SNI_GATE=true
    validate_strict_sni_gate_reality_server_names() { return 1; }
    preflight_tcppeek_before_cutover() { echo 'UNEXPECTED_PREFLIGHT'; }
    for mode in nginx-stream tcp-peek; do
        if preflight_entry_mode_before_cutover "$mode" >/dev/null; then
            echo "Unregistered REALITY SNI must stop entry preflight." >&2
            exit 1
        fi
    done
    preflight_entry_mode_before_cutover xray-fallback
)

(
    STRICT_SNI_GATE=true
    saved_state=''
    load_sni_stack_env() { return 0; }
    get_entry_mode() { echo xray-fallback; }
    confirm_danger() { return 0; }
    save_sni_stack_env() { saved_state="$STRICT_SNI_GATE"; }
    sync_strict_sni_gate_to_current_entry() { return 1; }
    set_strict_sni_gate false >/dev/null
    [[ "$saved_state" == false ]]
)

(
    load_sni_stack_env() { return 0; }
    get_entry_mode() { echo tcp-peek; }
    reapply_sni_stack_from_env() { [[ "$1" == --yes ]] && return 17; }
    result=0
    sync_xray_sni_routes_to_entry_mode >/dev/null || result=$?
    [[ "$result" == 17 ]]
)

(
    source src/vpso_mux_install.sh
    update_tmp=$(mktemp -d /tmp/vpso-mux-update-test.XXXXXX)
    trap 'rm -rf "$update_tmp"' EXIT
    vpso_mux_binary_path() { echo "$update_tmp/vpso-mux"; }
    vpso_mux_config_path() { echo "$update_tmp/config.yaml"; }
    vpso_mux_preflight_config_path() { echo "$update_tmp/preflight.yaml"; }
    load_sni_stack_env() { return 0; }
    confirm_risk_action() { return 0; }
    uname() { echo x86_64; }
    download_vpso_mux_binary() {
        [[ "$scenario" != download-fail ]] || return 1
        printf '#!/bin/sh\nexit %s\n' "$candidate_exit" > "$1"
        chmod 755 "$1"
    }
    systemctl() {
        case "$1" in
            is-active) [[ "$active" == 1 && "$3" == vpso-mux ]] ;;
            restart)
                echo "$2" >> "$update_tmp/restarts"
                [[ "$scenario" != restart-fail ]] || cmp -s "$(vpso_mux_binary_path)" "$update_tmp/original"
                ;;
            *) return 1 ;;
        esac
    }
    verify_public_443_listener_for_mode() {
        [[ "$scenario" != listener-fail ]] || cmp -s "$(vpso_mux_binary_path)" "$update_tmp/original"
    }
    printf '#!/bin/sh\nexit 42\n' > "$update_tmp/original"
    chmod 755 "$update_tmp/original"
    printf 'unchanged config\n' > "$update_tmp/config.yaml"
    for scenario in success inactive download-fail config-fail restart-fail listener-fail; do
        cp -p "$update_tmp/original" "$(vpso_mux_binary_path)"
        : > "$update_tmp/restarts"
        candidate_exit=0
        active=1
        [[ "$scenario" != config-fail ]] || candidate_exit=1
        [[ "$scenario" != inactive ]] || active=0
        result=0
        update_vpso_mux_binary >/dev/null 2>&1 || result=$?
        case "$scenario" in
            success|inactive)
                [[ "$result" == 0 ]]
                "$(vpso_mux_binary_path)"
                if [[ "$scenario" == inactive ]]; then
                    [[ ! -s "$update_tmp/restarts" ]]
                else
                    [[ "$(wc -l < "$update_tmp/restarts")" -eq 1 ]]
                fi
                ;;
            *)
                [[ "$result" != 0 ]]
                cmp "$(vpso_mux_binary_path)" "$update_tmp/original"
                case "$scenario" in
                    download-fail|config-fail) [[ ! -s "$update_tmp/restarts" ]] ;;
                    *) [[ "$(wc -l < "$update_tmp/restarts")" -eq 2 ]] ;;
                esac
                ;;
        esac
        [[ "$(cat "$update_tmp/config.yaml")" == 'unchanged config' ]]
    done
    scenario=success
    candidate_exit=0
    rm -f "$(vpso_mux_binary_path)"
    install_vpso_mux_binary
    "$(vpso_mux_binary_path)"
    scenario=download-fail
    install_vpso_mux_binary
)

echo "Smoke tests passed."
