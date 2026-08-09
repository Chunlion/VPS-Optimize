# shellcheck shell=bash
# Firewall rule management workflows.

port_connlimit_comment() {
    local port="$1"
    printf 'VPSO_CONN_LIMIT_PORT_%s' "$port"
}

is_valid_connlimit_value() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    value="${value#"${value%%[!0]*}"}"
    [[ -n "$value" && ${#value} -le 10 ]] || return 1
    (( 10#$value <= 4294967295 ))
}

ensure_connlimit_tool() {
    local cmd="$1"
    local family_label="$2"

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 ${cmd}，正在尝试安装 iptables 兼容工具...${PLAIN}" "${YELLOW}⚠️ ${cmd} not detected, trying to install iptables compatible tool...${PLAIN}" "${YELLOW}⚠️ ${cmd} не обнаружен, пытаюсь установить iptables-совместимый инструмент...${PLAIN}")"
    install_pkg iptables || true

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    echo -e "$(localized_text "${RED}❌ 未检测到 ${cmd}，无法写入 ${family_label} connlimit 规则。${PLAIN}" "${RED}❌ ${cmd} is not detected and the ${family_label} connlimit rule cannot be written.${PLAIN}" "${RED}❌ ${cmd} не обнаружен, и правило connlimit ${family_label} не может быть записано.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}请先安装 iptables/ip6tables 兼容工具，再重新进入本菜单。${PLAIN}" "${YELLOW}Please install the iptables/ip6tables compatible tool first, and then re-enter this menu.${PLAIN}" "${YELLOW}Сначала установите инструмент, совместимый с iptables/ip6tables, а затем повторно войдите в это меню.${PLAIN}")"
    return 1
}

try_load_connlimit_module() {
    if command -v modprobe >/dev/null 2>&1; then
        modprobe xt_connlimit >/dev/null 2>&1 || true
    fi
}

port_connlimit_runtime_rule_count() {
    local cmd="$1"
    local count

    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf '0'
        return 0
    fi

    count=$("$cmd" -S INPUT 2>/dev/null | grep -Fc 'VPSO_CONN_LIMIT_PORT_' || true)
    printf '%s' "${count:-0}"
}

port_connlimit_persisted_rule_count() {
    local file="$1"
    local count

    if [[ ! -f "$file" ]]; then
        printf '0'
        return 0
    fi

    count=$(grep -Fc 'VPSO_CONN_LIMIT_PORT_' "$file" 2>/dev/null || true)
    printf '%s' "${count:-0}"
}

port_connlimit_command_path() {
    local cmd="$1"
    local candidate

    if command -v "$cmd" >/dev/null 2>&1; then
        command -v "$cmd"
        return 0
    fi

    for candidate in "/usr/sbin/${cmd}" "/sbin/${cmd}" "/usr/bin/${cmd}" "/bin/${cmd}"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

port_connlimit_systemd_unit_exists() {
    local unit="$1"

    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl list-unit-files "${unit}.service" --no-legend 2>/dev/null | grep -q . && return 0
    systemctl list-units "${unit}.service" --all --no-legend 2>/dev/null | grep -q . && return 0
    return 1
}

port_connlimit_rhel_ipv4_persistence_available() {
    is_redhat || return 1
    port_connlimit_command_path iptables-save >/dev/null 2>&1 || return 1

    [[ -f /etc/sysconfig/iptables ]] && return 0
    port_connlimit_systemd_unit_exists iptables
}

port_connlimit_rhel_ipv6_persistence_available() {
    is_redhat || return 1
    port_connlimit_command_path ip6tables-save >/dev/null 2>&1 || return 1

    [[ -f /etc/sysconfig/ip6tables ]] && return 0
    port_connlimit_systemd_unit_exists ip6tables
}

port_connlimit_persistence_backend() {
    if port_connlimit_command_path netfilter-persistent >/dev/null 2>&1; then
        printf '%s\n' "netfilter-persistent"
        return 0
    fi

    if port_connlimit_rhel_ipv4_persistence_available; then
        printf '%s\n' "rhel-iptables-services"
        return 0
    fi

    printf '%s\n' "none"
}

port_connlimit_saved_file_for_family() {
    local family="$1"
    local backend="${2:-$(port_connlimit_persistence_backend)}"

    case "$backend:$family" in
        netfilter-persistent:4) printf '%s\n' "/etc/iptables/rules.v4" ;;
        netfilter-persistent:6) printf '%s\n' "/etc/iptables/rules.v6" ;;
        rhel-iptables-services:4) printf '%s\n' "/etc/sysconfig/iptables" ;;
        rhel-iptables-services:6) printf '%s\n' "/etc/sysconfig/ip6tables" ;;
        *) return 1 ;;
    esac
}

port_connlimit_saved_rule_count_for_family() {
    local family="$1"
    local backend="${2:-$(port_connlimit_persistence_backend)}"
    local file

    file=$(port_connlimit_saved_file_for_family "$family" "$backend" 2>/dev/null) || {
        printf '0'
        return 0
    }
    port_connlimit_persisted_rule_count "$file"
}

port_connlimit_runtime_rule_fingerprints_for_family() {
    local family="$1"
    local cmd="$2"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    "$cmd" -S INPUT 2>/dev/null | grep -F 'VPSO_CONN_LIMIT_PORT_' | sed "s/^/${family}:/" || true
}

port_connlimit_saved_rule_fingerprints_for_file() {
    local family="$1"
    local file="$2"

    [[ -f "$file" ]] || return 0
    grep -F 'VPSO_CONN_LIMIT_PORT_' "$file" 2>/dev/null | sed "s/^/${family}:/" || true
}

port_connlimit_runtime_rule_fingerprints() {
    {
        port_connlimit_runtime_rule_fingerprints_for_family "IPv4" iptables
        port_connlimit_runtime_rule_fingerprints_for_family "IPv6" ip6tables
    } | sort -u
}

port_connlimit_saved_rule_fingerprints_for_backend() {
    local backend="$1"
    local v4_file v6_file

    v4_file=$(port_connlimit_saved_file_for_family 4 "$backend" 2>/dev/null || true)
    v6_file=$(port_connlimit_saved_file_for_family 6 "$backend" 2>/dev/null || true)
    {
        [[ -n "$v4_file" ]] && port_connlimit_saved_rule_fingerprints_for_file "IPv4" "$v4_file"
        [[ -n "$v6_file" ]] && port_connlimit_saved_rule_fingerprints_for_file "IPv6" "$v6_file"
    } | sort -u
}

port_connlimit_known_saved_rule_fingerprints() {
    {
        port_connlimit_saved_rule_fingerprints_for_file "IPv4" /etc/iptables/rules.v4
        port_connlimit_saved_rule_fingerprints_for_file "IPv6" /etc/iptables/rules.v6
        port_connlimit_saved_rule_fingerprints_for_file "IPv4" /etc/sysconfig/iptables
        port_connlimit_saved_rule_fingerprints_for_file "IPv6" /etc/sysconfig/ip6tables
    } | sort -u
}

port_connlimit_fingerprint_count() {
    local data="$1"

    if [[ -z "$data" ]]; then
        printf '0'
    else
        printf '%s\n' "$data" | grep -c .
    fi
}

print_port_connlimit_health_summary() {
    local backend runtime_rules saved_rules known_saved_rules
    local runtime_count saved_count known_saved_count backend_label consistency risk

    backend=$(port_connlimit_persistence_backend)
    runtime_rules=$(port_connlimit_runtime_rule_fingerprints)
    saved_rules=$(port_connlimit_saved_rule_fingerprints_for_backend "$backend")
    known_saved_rules=$(port_connlimit_known_saved_rule_fingerprints)
    runtime_count=$(port_connlimit_fingerprint_count "$runtime_rules")
    saved_count=$(port_connlimit_fingerprint_count "$saved_rules")
    known_saved_count=$(port_connlimit_fingerprint_count "$known_saved_rules")

    case "$backend" in
        netfilter-persistent) backend_label="${GREEN}netfilter-persistent${PLAIN}" ;;
        rhel-iptables-services) backend_label="${GREEN}rhel-iptables-services${PLAIN}" ;;
        *) backend_label="$(localized_text "${YELLOW}未检测到可用后端${PLAIN}" "${YELLOW}No available backend detected${PLAIN}" "${YELLOW}Доступная бэкенд не обнаружена${PLAIN}")" ;;
    esac

    if [[ "$backend" == "none" ]]; then
        consistency="$(localized_text "${YELLOW}未检测（无可用持久化后端）${PLAIN}" "${YELLOW}Not detected (no persistence backend available)${PLAIN}" "${YELLOW}Не обнаружен (бэкенд сохраняемости недоступна)${PLAIN}")"
    elif [[ "$runtime_rules" == "$saved_rules" ]]; then
        consistency="$(localized_text "${GREEN}一致${PLAIN}" "${GREEN}Is consistent with${PLAIN}" "${GREEN}соответствует .${PLAIN}")"
    else
        consistency="$(localized_text "${YELLOW}不一致${PLAIN}" "${YELLOW}Is inconsistent with${PLAIN}" "${YELLOW}несовместим с .${PLAIN}")"
    fi

    if [[ "$backend" == "none" && "$runtime_count" -gt 0 ]]; then
        risk="$(localized_text "${YELLOW}存在：运行时规则未接入可用持久化后端，重启后可能丢失或恢复旧快照。${PLAIN}" "${YELLOW}Exists: The runtime rule is not connected to the available persistence backend, and old snapshots may be lost or restored after restarting.${PLAIN}" "${YELLOW}существует: правило времени выполнения не подключено к доступной серверной части хранилища, и старые снимки могут быть потеряны или восстановлены после перезапуска.${PLAIN}")"
    elif [[ "$backend" == "none" && "$known_saved_count" -gt 0 ]]; then
        risk="$(localized_text "${YELLOW}存在：发现保存文件里仍有脚本规则标记，但当前无可用后端，重启恢复行为需手动确认。${PLAIN}" "${YELLOW}Exists: It is found that there are still script rule tags in the saved file, but there is currently no available backend. The restart recovery behavior needs to be confirmed manually.${PLAIN}" "${YELLOW}существует: обнаружено, что в сохраненном файле все еще есть теги правил сценария, но в настоящее время доступной серверной части нет. Поведение перезапуска и восстановления необходимо подтвердить вручную.${PLAIN}")"
    elif [[ "$backend" != "none" && "$runtime_count" -gt 0 && "$saved_count" -eq 0 ]]; then
        risk="$(localized_text "${YELLOW}存在：运行时规则尚未出现在当前保存文件中，重启后可能丢失。${PLAIN}" "${YELLOW}Exists: The runtime rule does not yet appear in the current save file and may be lost after restarting.${PLAIN}" "${YELLOW}существует: правило времени выполнения еще не отображается в текущем файле сохранения и может быть потеряно после перезапуска.${PLAIN}")"
    elif [[ "$backend" != "none" && "$runtime_count" -eq 0 && "$saved_count" -gt 0 ]]; then
        risk="$(localized_text "${YELLOW}存在：运行时没有脚本规则，但保存文件仍有旧标记，重启后可能恢复旧规则。${PLAIN}" "${YELLOW}Exists: There are no script rules when running, but the saved file still has old tags. The old rules may be restored after restarting.${PLAIN}" "${YELLOW}существует: при запуске нет правил сценария, но сохраненный файл все еще имеет старые теги. Старые правила могут быть восстановлены после перезапуска.${PLAIN}")"
    elif [[ "$backend" != "none" && "$runtime_rules" != "$saved_rules" ]]; then
        risk="$(localized_text "${YELLOW}存在：运行时规则与保存文件不同，建议到 [8] -> [5] -> [5] 重新保存/检查。${PLAIN}" "${YELLOW}Exists: The runtime rules are different from the saved files. It is recommended to go to [8] -> [5] -> [5] to resave/check.${PLAIN}" "${YELLOW}существует: правила времени выполнения отличаются от правил сохраненных файлов. Рекомендуется перейти к [8] -> [5] -> [5] для пересохранения/проверки.${PLAIN}")"
    else
        risk="$(localized_text "${GREEN}未发现明显丢失/旧快照风险${PLAIN}" "${GREEN}No obvious risk of loss/old snapshot found${PLAIN}" "${GREEN}Нет очевидного риска потери/старый снимок не найден${PLAIN}")"
    fi

    echo -e "$(localized_text "${CYAN}🔒 connlimit 持久化摘要${PLAIN}" "${CYAN}🔒 connlimit persistence summary${PLAIN}" "${CYAN}🔒 сводка о постоянстве connlimit${PLAIN}")"
    if [[ "$runtime_count" -gt 0 ]]; then
        echo -e "$(localized_text "脚本规则状态       : [ ${GREEN}存在${PLAIN} ]  运行时: ${CYAN}${runtime_count}${PLAIN} 条" "Script rule status: [ ${GREEN}Exists${PLAIN} ] Runtime: ${CYAN}${runtime_count}${PLAIN}" "Статус правила сценария: [ ${GREEN}существует${PLAIN} ] Время выполнения: ${CYAN}${runtime_count}${PLAIN}")"
    else
        echo -e "$(localized_text "脚本规则状态       : [ ${BLUE}未检测到运行时规则${PLAIN} ]" "Script rule status: [${BLUE}Runtime rule${PLAIN} not detected]" "Статус правила сценария: [${BLUE}Правило времени выполнения${PLAIN} не обнаружено]")"
    fi
    echo -e "$(localized_text "可用持久化后端     : [ $backend_label ]" "Available persistence backends: [ $backend_label ]" "Доступные серверные части персистентности: [ $backend_label ]")"
    echo -e "$(localized_text "运行时/保存文件    : [ $consistency ]  保存文件: ${CYAN}${saved_count}${PLAIN} 条" "Runtime/save file: [ $consistency ] Save file: ${CYAN}${saved_count}${PLAIN}" "Файл времени выполнения/сохранения: [ $consistency ] Файл сохранения: ${CYAN}${saved_count}${PLAIN}")"
    echo -e "$(localized_text "重启风险提示       : [ $risk ]" "Restart risk warning: [ $risk ]" "Предупреждение о риске перезапуска: [ $risk ]")"
}

print_port_connlimit_persistence_unavailable() {
    echo -e "$(localized_text "${YELLOW}⚠️ 未检测到本脚本可可靠调用的 connlimit 持久化保存能力。${PLAIN}" "${YELLOW}⚠️ The connlimit persistence capability that this script can call reliably has not been detected.${PLAIN}" "${YELLOW}⚠️ Возможность сохранения connlimit, которую этот сценарий может надежно вызывать, не обнаружена.${PLAIN}")"
    if is_debian; then
        echo -e "$(localized_text "${YELLOW}Debian/Ubuntu 可安装并启用 iptables-persistent / netfilter-persistent 后再保存。${PLAIN}" "${YELLOW}Debian/Ubuntu can install and enable iptables-persistent / netfilter-persistent and then save.${PLAIN}" "${YELLOW}Debian/Ubuntu может установить и включить iptables-persistent/netfilter-persistent, а затем сохранить.${PLAIN}")"
    elif is_redhat; then
        echo -e "$(localized_text "${YELLOW}RHEL/Rocky/Alma/CentOS Stream 仅在检测到已有 iptables-services（iptables.service 或 /etc/sysconfig/iptables）时自动保存。${PLAIN}" "${YELLOW}RHEL/Rocky/Alma/CentOS Stream is only automatically saved if an existing iptables-services (iptables.service or /etc/sysconfig/iptables) is detected.${PLAIN}" "${YELLOW}Поток RHEL/Rocky/Alma/CentOS автоматически сохраняется только в том случае, если обнаружены существующие службы iptables (iptables.service или /etc/sysconfig/iptables).${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}当前发行版未提供本脚本可验证的 iptables 持久化路径，请使用系统自带机制手动保存。${PLAIN}" "${YELLOW}The current release version of does not provide a iptables persistence path that can be verified by this script. Please use the system's own mechanism to save it manually.${PLAIN}" "${YELLOW}Текущая версия не предоставляет путь сохранения iptables, который можно проверить с помощью этого сценария. Пожалуйста, используйте собственный механизм системы, чтобы сохранить его вручную.${PLAIN}")"
    fi
    echo -e "$(localized_text "${YELLOW}当前 connlimit 规则只在本次运行期生效，重启后可能丢失或恢复旧快照。${PLAIN}" "${YELLOW}The current connlimit rule only takes effect during this running period. Old snapshots may be lost or restored after restarting.${PLAIN}" "${YELLOW}Текущее правило connlimit вступает в силу только в течение этого периода работы. Старые снимки могут быть потеряны или восстановлены после перезапуска.${PLAIN}")"
}

print_port_connlimit_persistence_status() {
    local v4_runtime v6_runtime v4_saved v6_saved backend
    local v4_file deb_v4_saved deb_v6_saved rhel_v4_saved rhel_v6_saved

    backend=$(port_connlimit_persistence_backend)
    v4_runtime=$(port_connlimit_runtime_rule_count iptables)
    v6_runtime=$(port_connlimit_runtime_rule_count ip6tables)
    v4_saved=$(port_connlimit_saved_rule_count_for_family 4 "$backend")
    v6_saved=$(port_connlimit_saved_rule_count_for_family 6 "$backend")
    deb_v4_saved=$(port_connlimit_persisted_rule_count /etc/iptables/rules.v4)
    deb_v6_saved=$(port_connlimit_persisted_rule_count /etc/iptables/rules.v6)
    rhel_v4_saved=$(port_connlimit_persisted_rule_count /etc/sysconfig/iptables)
    rhel_v6_saved=$(port_connlimit_persisted_rule_count /etc/sysconfig/ip6tables)
    v4_file=$(port_connlimit_saved_file_for_family 4 "$backend" 2>/dev/null || true)

    echo -e "$(localized_text "${CYAN}持久化检查：${PLAIN}" "${CYAN}Persistence check:${PLAIN}" "${CYAN}Проверка устойчивости :${PLAIN}")"
    echo "$(localized_text "  运行时规则：IPv4 ${v4_runtime} 条，IPv6 ${v6_runtime} 条。" "Runtime rules: IPv4 ${v4_runtime}, IPv6 ${v6_runtime}." "Правила выполнения: IPv4 ${v4_runtime}, IPv6 ${v6_runtime}.")"
    echo "$(localized_text "  Debian/Ubuntu 保存文件：/etc/iptables/rules.v4 中 ${deb_v4_saved} 条，/etc/iptables/rules.v6 中 ${deb_v6_saved} 条。" "Debian/Ubuntu save files: ${deb_v4_saved} in /etc/iptables/rules.v4, ${deb_v6_saved} in /etc/iptables/rules.v6." "Файлы сохранения Debian/Ubuntu: ${deb_v4_saved} в /etc/iptables/rules.v4, ${deb_v6_saved} в /etc/iptables/rules.v6.")"
    echo "$(localized_text "  RHEL 系列保存文件：/etc/sysconfig/iptables 中 ${rhel_v4_saved} 条，/etc/sysconfig/ip6tables 中 ${rhel_v6_saved} 条。" "RHEL series save files: ${rhel_v4_saved} in /etc/sysconfig/iptables, ${rhel_v6_saved} in /etc/sysconfig/ip6tables." "Файлы сохранения серии RHEL: ${rhel_v4_saved} в /etc/sysconfig/iptables, ${rhel_v6_saved} в /etc/sysconfig/ip6tables.")"

    if [[ "$backend" == "netfilter-persistent" ]]; then
        echo -e "$(localized_text "${GREEN}  已检测到 netfilter-persistent；添加/删除 connlimit 后会自动尝试保存，也可用本菜单 [5] 手动检查/保存。${PLAIN}" "${GREEN}Netfilter-persistent has been detected; after adding/deleting connlimit, it will automatically try to save. You can also use this menu [5] to manually check/save.${PLAIN}" "${GREEN}Обнаружен постоянный сетевой фильтр ; после добавления/удаления connlimit автоматически попытается сохранить. Вы также можете использовать это меню [5] для проверки/сохранения вручную.${PLAIN}")"
    elif command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W -f='${Status}' iptables-persistent 2>/dev/null | grep -q 'install ok installed'; then
        echo -e "$(localized_text "${YELLOW}  已检测到 iptables-persistent 包，但未检测到 netfilter-persistent 命令；请确认 /usr/sbin 是否在 PATH。${PLAIN}" "${YELLOW}The iptables-persistent package has been detected, but the netfilter-persistent command has not been detected; please confirm whether /usr/sbin is in PATH.${PLAIN}" "${YELLOW}Обнаружен постоянный пакет iptables, но команда netfilter-persistent не обнаружена; пожалуйста, подтвердите, находится ли /usr/sbin в PATH.${PLAIN}")"
    elif [[ "$backend" == "rhel-iptables-services" ]]; then
        echo -e "$(localized_text "${GREEN}  已检测到 RHEL 系列已有 iptables-services 持久化路径；添加/删除 connlimit 后会自动写入 ${v4_file:-/etc/sysconfig/iptables}。${PLAIN}" "${GREEN}Has detected that the RHEL series already has the iptables-services persistence path; ${v4_file:-/etc/sysconfig/iptables} will be automatically written after adding/deleting the connlimit.${PLAIN}" "${GREEN}обнаружил, что серия RHEL уже имеет путь сохранения iptables-services; ${v4_file:-/etc/sysconfig/iptables} будет автоматически записан после добавления/удаления connlimit.${PLAIN}")"
        if ! port_connlimit_rhel_ipv6_persistence_available; then
            echo -e "$(localized_text "${YELLOW}  IPv6 未检测到 ip6tables.service 或 /etc/sysconfig/ip6tables；如有 IPv6 connlimit 规则，可能只能在本次运行期生效。${PLAIN}" "${YELLOW}IPv6 ip6tables.service or /etc/sysconfig/ip6tables is not detected; if there is a IPv6 connlimit rule, it may only take effect during this run.${PLAIN}" "${YELLOW}IPv6 ip6tables.service или /etc/sysconfig/ip6tables не обнаружен; если существует правило connlimit IPv6, оно может вступить в силу только во время этого запуска.${PLAIN}")"
        fi
    else
        print_port_connlimit_persistence_unavailable
    fi

    if [[ "$backend" == "netfilter-persistent" ]] && command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files netfilter-persistent.service --no-legend 2>/dev/null | grep -q .; then
        local enabled active
        enabled=$(systemctl is-enabled netfilter-persistent 2>/dev/null || true)
        active=$(systemctl is-active netfilter-persistent 2>/dev/null || true)
        echo "$(localized_text "  开机恢复服务：netfilter-persistent enabled=${enabled:-unknown}, active=${active:-unknown}。" "Restore service after booting: netfilter-persistent enabled=${enabled:-unknown}, active=${active:-unknown}." "Восстановление службы после загрузки: netfilter-persistent Enabled=${enabled:-unknown}, active=${active:-unknown}.")"
    fi
    if port_connlimit_systemd_unit_exists iptables; then
        local iptables_enabled iptables_active
        iptables_enabled=$(systemctl is-enabled iptables 2>/dev/null || true)
        iptables_active=$(systemctl is-active iptables 2>/dev/null || true)
        echo "$(localized_text "  开机恢复服务：iptables enabled=${iptables_enabled:-unknown}, active=${iptables_active:-unknown}。" "Restore service after booting: iptables enabled=${iptables_enabled:-unknown}, active=${iptables_active:-unknown}." "Восстановление службы после загрузки: iptables включен=${iptables_enabled:-unknown}, активен=${iptables_active:-unknown}.")"
    fi
    if port_connlimit_systemd_unit_exists ip6tables; then
        local ip6tables_enabled ip6tables_active
        ip6tables_enabled=$(systemctl is-enabled ip6tables 2>/dev/null || true)
        ip6tables_active=$(systemctl is-active ip6tables 2>/dev/null || true)
        echo "$(localized_text "  开机恢复服务：ip6tables enabled=${ip6tables_enabled:-unknown}, active=${ip6tables_active:-unknown}。" "Restore service at startup: ip6tables enabled=${ip6tables_enabled:-unknown}, active=${ip6tables_active:-unknown}." "Восстановление службы при запуске: ip6tables Enabled=${ip6tables_enabled:-unknown}, active=${ip6tables_active:-unknown}.")"
    fi

    if (( v4_runtime > 0 && v4_saved == 0 )) || (( v6_runtime > 0 && v6_saved == 0 )); then
        echo -e "$(localized_text "${YELLOW}  提示：检测到运行时 connlimit 规则尚未出现在当前可用的保存文件中，重启后可能丢失。${PLAIN}" "${YELLOW}Tip: It was detected that the runtime connlimit rule does not yet appear in the currently available save file and may be lost after restarting.${PLAIN}" "${YELLOW}Совет. Было обнаружено, что правило connlimit во время выполнения еще не отображается в доступном на данный момент файле сохранения и может быть потеряно после перезапуска.${PLAIN}")"
    elif (( v4_runtime + v6_runtime == 0 && v4_saved + v6_saved > 0 )); then
        echo -e "$(localized_text "${YELLOW}  提示：运行时没有脚本规则，但保存文件里仍有旧标记；如不更新快照，重启后可能恢复旧规则。${PLAIN}" "${YELLOW}Tip: There are no script rules when running, but there are still old marks in the saved file; if the snapshot is not updated, the old rules may be restored after restarting.${PLAIN}" "${YELLOW}Совет: При запуске скрипта правила отсутствуют, но в сохраненном файле все еще остаются старые отметки; если снимок не обновляется, старые правила могут быть восстановлены после перезапуска.${PLAIN}")"
    elif (( v4_runtime + v6_runtime > 0 )); then
        echo -e "$(localized_text "${GREEN}  已在当前可用的保存文件中检测到脚本规则标记，重启恢复还取决于对应恢复服务是否启用。${PLAIN}" "${GREEN}A script rule tag has been detected in a currently available save file. Restarting recovery also depends on whether the corresponding recovery service is enabled.${PLAIN}" "${GREEN}В доступном в данный момент файле сохранения обнаружен тег правила сценария. Перезапуск восстановления также зависит от того, включена ли соответствующая служба восстановления.${PLAIN}")"
    else
        echo -e "$(localized_text "${BLUE}  当前没有检测到脚本添加的运行时 connlimit 规则。${PLAIN}" "${BLUE}Runtime connlimit rules added by the script are not currently detected.${PLAIN}" "${BLUE}Правила connlimit во время выполнения, добавленные сценарием, в настоящее время не обнаружены.${PLAIN}")"
    fi
}

enable_port_connlimit_persistence_service() {
    local backend="${1:-$(port_connlimit_persistence_backend)}"

    if [[ "$backend" == "netfilter-persistent" ]] && command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files netfilter-persistent.service --no-legend 2>/dev/null | grep -q .; then
        if systemctl enable netfilter-persistent >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ 已确认 netfilter-persistent 开机恢复服务启用。${PLAIN}" "${GREEN}✅ It has been confirmed that the netfilter-persistent boot recovery service is enabled.${PLAIN}" "${GREEN}. Было подтверждено, что служба восстановления загрузки с постоянным фильтром netfilter включена.${PLAIN}")"
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 未能启用 netfilter-persistent 服务；规则文件已保存，但开机恢复状态需要手动确认。${PLAIN}" "${YELLOW}⚠️ Failed to enable the netfilter-persistent service; the rule file has been saved, but the boot recovery status requires manual confirmation.${PLAIN}" "${YELLOW}⚠️ Не удалось включить постоянную службу netfilter; файл правил сохранен, но статус восстановления загрузки требует подтверждения вручную.${PLAIN}")"
        fi
    fi
    if [[ "$backend" == "rhel-iptables-services" ]] && port_connlimit_systemd_unit_exists iptables; then
        if systemctl enable iptables >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ 已确认 iptables 开机恢复服务启用。${PLAIN}" "${GREEN}✅ It is confirmed that iptables boot recovery service is enabled.${PLAIN}" "${GREEN}. Подтверждено, что служба восстановления загрузки iptables включена.${PLAIN}")"
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 未能启用 iptables 服务；IPv4 规则文件已保存，但开机恢复状态需要手动确认。${PLAIN}" "${YELLOW}⚠️ Failed to enable the iptables service; IPv4 rule file has been saved, but the power-on recovery status requires manual confirmation.${PLAIN}" "${YELLOW}⚠️ Не удалось включить службу iptables; Файл правил IPv4 сохранен, но состояние восстановления при включении требует подтверждения вручную.${PLAIN}")"
        fi
    fi
    if [[ "$backend" == "rhel-iptables-services" ]] && port_connlimit_systemd_unit_exists ip6tables; then
        if systemctl enable ip6tables >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ 已确认 ip6tables 开机恢复服务启用。${PLAIN}" "${GREEN}✅ It is confirmed that the ip6tables boot recovery service is enabled.${PLAIN}" "${GREEN}✅ Подтверждено, что служба восстановления загрузки ip6tables включена.${PLAIN}")"
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 未能启用 ip6tables 服务；IPv6 规则文件已保存，但开机恢复状态需要手动确认。${PLAIN}" "${YELLOW}⚠️ Failed to enable the ip6tables service; IPv6 rule file has been saved, but the boot recovery state needs to be manually confirmed.${PLAIN}" "${YELLOW}⚠️ Не удалось включить службу ip6tables; Файл правил IPv6 сохранен, но состояние восстановления загрузки необходимо подтвердить вручную.${PLAIN}")"
        fi
    fi
}

save_rhel_port_connlimit_family() {
    local save_cmd="$1"
    local file="$2"
    local label="$3"
    local tmp_file err_file output

    tmp_file=$(mktemp /tmp/vps-connlimit-rules.XXXXXX) || return 1
    err_file=$(mktemp /tmp/vps-connlimit-save.XXXXXX) || {
        rm -f "$tmp_file"
        return 1
    }
    if "$save_cmd" > "$tmp_file" 2>"$err_file"; then
        output=$(<"$err_file")
        mkdir -p "$(dirname "$file")" || {
            rm -f "$tmp_file"
            rm -f "$err_file"
            echo -e "$(localized_text "${RED}❌ 无法创建 $(dirname "$file")，${label} connlimit 持久化保存失败。${PLAIN}" "${RED}❌ Unable to create $(dirname \"$file\"), ${label} connlimit persistent save failed.${PLAIN}" "${RED}❌ Невозможно создать $(dirname \"$file\"), не удалось сохранить постоянное сохранение connlimit ${label}.${PLAIN}")"
            return 1
        }
        if cp "$tmp_file" "$file"; then
            chmod 600 "$file" 2>/dev/null || true
            rm -f "$tmp_file"
            rm -f "$err_file"
            echo -e "$(localized_text "${GREEN}✅ 已写入 ${file}，${label} connlimit 快照已保存。${PLAIN}" "${GREEN}✅ ${file} has been written, ${label} connlimit snapshot has been saved.${PLAIN}" "${GREEN}✅ ${file} записан, снапшот connlimit ${label} сохранен.${PLAIN}")"
            return 0
        fi
        rm -f "$tmp_file"
        rm -f "$err_file"
        echo -e "$(localized_text "${RED}❌ 写入 ${file} 失败，${label} connlimit 规则仍可能只在运行时有效。${PLAIN}" "${RED}❌ Writing to ${file} failed, ${label} connlimit rules may still only be valid at runtime.${PLAIN}" "${RED}❌ Не удалось выполнить запись в ${file}, правила connlimit ${label} все еще могут быть действительны только во время выполнения.${PLAIN}")"
        return 1
    fi

    output=$(<"$err_file")
    rm -f "$tmp_file"
    rm -f "$err_file"
    echo -e "$(localized_text "${RED}❌ ${save_cmd} 执行失败，${label} connlimit 持久化保存失败：${output}${PLAIN}" "${RED}❌ ${save_cmd} execution failed, ${label} connlimit persistent save failed: ${output}${PLAIN}" "${RED}❌ ${save_cmd} не удалось выполнить, ${label} постоянное сохранение connlimit не удалось: ${output}${PLAIN}")"
    return 1
}

save_rhel_port_connlimit_persistence() {
    local rc=0
    local iptables_save ip6tables_save
    local v6_runtime v6_saved

    iptables_save=$(port_connlimit_command_path iptables-save 2>/dev/null || true)
    if [[ -z "$iptables_save" ]]; then
        echo -e "$(localized_text "${RED}❌ 未检测到 iptables-save，无法写入 RHEL 系列 IPv4 connlimit 持久化文件。${PLAIN}" "${RED}❌ iptables-save not detected, unable to write to RHEL series IPv4 connlimit persistence file.${PLAIN}" "${RED}❌ iptables-сохранение не обнаружено, невозможно записать в файл постоянства connlimit серии RHEL IPv4.${PLAIN}")"
        rc=1
    else
        save_rhel_port_connlimit_family "$iptables_save" "/etc/sysconfig/iptables" "IPv4" || rc=1
    fi

    v6_runtime=$(port_connlimit_runtime_rule_count ip6tables)
    v6_saved=$(port_connlimit_persisted_rule_count /etc/sysconfig/ip6tables)
    if port_connlimit_rhel_ipv6_persistence_available; then
        ip6tables_save=$(port_connlimit_command_path ip6tables-save 2>/dev/null || true)
        save_rhel_port_connlimit_family "$ip6tables_save" "/etc/sysconfig/ip6tables" "IPv6" || rc=1
    elif (( v6_runtime > 0 || v6_saved > 0 )); then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 RHEL IPv6 持久化路径；当前 IPv6 connlimit 规则或旧快照无法由脚本可靠保存。${PLAIN}" "${YELLOW}⚠️ RHEL IPv6 persistence path not detected; current IPv6 connlimit rules or old snapshots cannot be reliably saved by the script.${PLAIN}" "${YELLOW}⚠️ Путь сохранения RHEL IPv6 не обнаружен; текущие правила connlimit IPv6 или старые снимки не могут быть надежно сохранены сценарием.${PLAIN}")"
        rc=1
    fi

    enable_port_connlimit_persistence_service "rhel-iptables-services"
    print_port_connlimit_persistence_status
    return "$rc"
}

save_port_connlimit_persistence() {
    local output backend
    local v4_runtime v6_runtime v4_saved v6_saved

    backend=$(port_connlimit_persistence_backend)
    if [[ "$backend" == "none" ]]; then
        print_port_connlimit_persistence_unavailable
        return 1
    fi

    if [[ "$backend" == "rhel-iptables-services" ]]; then
        save_rhel_port_connlimit_persistence
        return $?
    fi

    local netfilter_cmd
    netfilter_cmd=$(port_connlimit_command_path netfilter-persistent)
    if output=$("$netfilter_cmd" save 2>&1); then
        echo -e "$(localized_text "${GREEN}✅ 已执行 netfilter-persistent save，当前 iptables/ip6tables 快照已写入持久化文件。${PLAIN}" "${GREEN}✅ netfilter-persistent save has been executed, and the current iptables/ip6tables snapshot has been written to the persistent file.${PLAIN}" "${GREEN}Сохранение веще netfilter-persistent выполнено, и текущий снимок iptables/ip6tables записан в постоянный файл.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ netfilter-persistent save 执行失败：${output}${PLAIN}" "${RED}❌ netfilter-persistent save execution failed: ${output}${PLAIN}" "${RED}❌ не удалось выполнить постоянное сохранение netfilter: ${output}${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}本次不会假装已保存；当前 connlimit 规则仍可能只在运行时有效。${PLAIN}" "${YELLOW}Will not pretend to be saved this time; current connlimit rules may still only be valid at runtime.${PLAIN}" "${YELLOW}на этот раз не будет притворяться сохраненным; текущие правила connlimit могут по-прежнему действовать только во время выполнения.${PLAIN}")"
        return 1
    fi

    enable_port_connlimit_persistence_service "$backend"
    print_port_connlimit_persistence_status

    v4_runtime=$(port_connlimit_runtime_rule_count iptables)
    v6_runtime=$(port_connlimit_runtime_rule_count ip6tables)
    v4_saved=$(port_connlimit_saved_rule_count_for_family 4 "$backend")
    v6_saved=$(port_connlimit_saved_rule_count_for_family 6 "$backend")

    if (( v4_runtime > 0 && v4_saved == 0 )) || (( v6_runtime > 0 && v6_saved == 0 )); then
        echo -e "$(localized_text "${RED}❌ 保存后仍未在当前持久化文件中检测到脚本规则标记，请不要认为重启后一定会恢复。${PLAIN}" "${RED}❌ The script rule mark is still not detected in the current persistence file after saving. Please do not think that it will be restored after restarting.${PLAIN}" "${RED}❌ Метка правила сценария по-прежнему не обнаружена в текущем файле персистентности после сохранения. Пожалуйста, не думайте, что он восстановится после перезагрузки.${PLAIN}")"
        return 1
    fi

    return 0
}

auto_save_port_connlimit_persistence_after_change() {
    local action_label="$1"

    echo ""
    echo -e "$(localized_text "${CYAN}正在尝试自动保存 connlimit 持久化快照（${action_label} 后刷新）...${PLAIN}" "${CYAN}Is trying to automatically save the connlimit persistence snapshot (refreshed after ${action_label})...${PLAIN}" "${CYAN}пытается автоматически сохранить снимок состояния connlimit (обновляется после ${action_label})...${PLAIN}")"
    if save_port_connlimit_persistence; then
        echo -e "$(localized_text "${GREEN}✅ connlimit 持久化快照已刷新。${PLAIN}" "${GREEN}✅ connlimit persistence snapshot has been refreshed.${PLAIN}" "${GREEN}Снимок состояния постоянства connlimit ✅ обновлен.${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}⚠️ connlimit 运行时规则已按上方结果处理，但当前无法确认重启后保留。${PLAIN}" "${YELLOW}⚠️ The connlimit runtime rule has been processed according to the above results, but it is currently unable to confirm that it will be retained after restarting.${PLAIN}" "${YELLOW}⚠️ Правило времени выполнения connlimit было обработано в соответствии с приведенными выше результатами, но в настоящее время невозможно подтвердить, что оно будет сохранено после перезапуска.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}请按提示补齐系统持久化能力，或在确认发行版机制后手动保存；不要默认重启后仍存在。${PLAIN}" "${YELLOW}Please follow the prompts to complete the system persistence capability, or save it manually after confirming the release mechanism; do not default to it persisting after restarting.${PLAIN}" "${YELLOW}Следуйте инструкциям, чтобы завершить настройку сохранения системы, или сохраните ее вручную после подтверждения механизма выпуска; не по умолчанию сохраняйте его после перезапуска.${PLAIN}")"
        return 1
    fi
}

func_save_port_connlimit_persistence() {
    print_port_connlimit_persistence_status
    echo ""
    confirm_risk_action "$(localized_text "保存端口并发连接限制持久化快照" "Save port concurrent connection limit persistent snapshot" "Сохранить постоянный снимок ограничения количества одновременных подключений к порту")" \
        "$(localized_text "按当前系统已检测到的持久化机制保存 iptables/ip6tables 快照；Debian/Ubuntu 优先 netfilter-persistent，RHEL 系列优先已有 iptables-services" "Save the iptables/ip6tables snapshot according to the persistence mechanism detected by the current system; Debian/Ubuntu gives priority to netfilter-persistent, and RHEL series gives priority to existing iptables-services" "Сохраните снимок iptables/ip6tables в соответствии с механизмом сохранения, обнаруженным текущей системой; Debian/Ubuntu отдает приоритет постоянным службам netfilter, а серия RHEL отдает приоритет существующим службам iptables.")" \
        "$(localized_text "添加或删除 connlimit 规则后脚本会自动尝试保存；本入口用于手动检查或失败后重试" "After adding or deleting the connlimit rule, the script will automatically try to save; this entry is used for manual checking or retrying after failure." "После добавления или удаления правила connlimit скрипт автоматически попытается сохранить его; эта запись используется для ручной проверки или повторной попытки после неудачи.")" \
        "$(localized_text "本操作不清空运行时规则，不改写 UFW/firewalld 放行配置；它只刷新额外 connlimit 规则所在的 iptables 快照。" "This operation does not clear the runtime rules and does not rewrite the UFW/firewalld release configuration; it only refreshes the iptables snapshot where the additional connlimit rules are located." "Эта операция не очищает правила времени выполнения и не перезаписывает конфигурацию выпуска UFW/firewalld; он обновляет только снимок iptables, в котором расположены дополнительные правила connlimit.")" || {
        echo -e "$(localized_text "${BLUE}已取消保存端口并发连接限制持久化快照。${PLAIN}" "${BLUE}The port concurrent connection limit persistent snapshot has been canceled.${PLAIN}" "${BLUE}Постоянный снимок ограничения количества одновременных подключений к порту был отменен.${PLAIN}")"
        return 0
    }

    save_port_connlimit_persistence
}

port_connlimit_loopback_only_listener() {
    local port="$1"
    command -v ss >/dev/null 2>&1 || return 1

    ss -Htlpn 2>/dev/null | awk -v port="$port" '
        function is_target(addr) {
            return addr ~ (":" port "$") || addr ~ ("\\]:" port "$")
        }
        is_target($4) {
            if ($4 ~ /^(127\.0\.0\.1|localhost):/ || $4 ~ /^\[::1\]:/) {
                loopback = 1
            } else {
                public = 1
            }
        }
        END {
            exit (loopback && !public ? 0 : 1)
        }
    '
}

print_port_connlimit_scope_notice() {
    local port="$1"

    echo -e "$(localized_text "${YELLOW}说明：本功能写入的是额外 iptables/ip6tables connlimit 规则，不等同于 UFW/firewalld 的端口放行规则。${PLAIN}" "${YELLOW}Description: This function writes additional iptables/ip6tables connlimit rules, which are not equivalent to the port allow rules of UFW/firewalld.${PLAIN}" "${YELLOW}Описание: Эта функция записывает дополнительные правила connlimit iptables/ip6tables, которые не эквивалентны правилам освобождения портов UFW/firewalld.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}默认按“每个来源 IP”限制 TCP 并发连接数，不做全局总连接数限制。${PLAIN}" "${YELLOW}By default, the limit applies per source IP, not to the global connection total.${PLAIN}" "${YELLOW}По умолчанию ограничение применяется отдельно к каждому исходному IP-адресу, а не к общему числу соединений.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}添加/删除后会自动尝试刷新持久化快照；系统不支持时会明确提示只在本次运行期生效。${PLAIN}" "${YELLOW}After is added/deleted, it will automatically try to refresh the persistent snapshot; if the system does not support it, it will clearly prompt that it will only take effect during this running period.${PLAIN}" "${YELLOW}После добавления/удаления он автоматически попытается обновить постоянный снимок; если система его не поддерживает, она четко сообщит, что оно вступит в силу только в течение этого периода работы.${PLAIN}")"

    if [[ "$port" == "443" ]]; then
        echo -e "$(localized_text "${RED}⚠️ 443 强提醒：如果当前启用了 443 单入口/端口复用，本限制会作用于整个公网 443。${PLAIN}" "${RED}⚠️ 443 strong reminder: If 443 shared entry/port reuse is currently enabled, this restriction will apply to the entire public port 443.${PLAIN}" "${RED}⚠️ 443 Настоятельное напоминание: если в настоящее время включено мультиплексирование одной записи/порта 443, это ограничение будет применяться ко всей публичного порта 443.${PLAIN}")"
        echo -e "$(localized_text "${RED}它不能精准限制某一个 Xray/3x-ui 入站、某一个 SNI、某一个 UUID 或某一个用户。${PLAIN}" "${RED}Cannot accurately restrict the inbound of a certain Xray/3x-ui, a certain SNI, a certain UUID or a certain user.${PLAIN}" "${RED}не может точно ограничить входящее подключение определенного Xray/3x-ui, определенного SNI, определенного UUID или определенного пользователя.${PLAIN}")"
    fi

    if port_connlimit_loopback_only_listener "$port"; then
        echo -e "$(localized_text "${YELLOW}⚠️ 检测到该端口可能只监听 127.0.0.1/::1。本功能建议限制公网监听端口。${PLAIN}" "${YELLOW}⚠️ Detected that this port may only be listening on 127.0.0.1/::1. This feature recommends limiting public listening ports.${PLAIN}" "${YELLOW}⚠️ Обнаружено, что этот порт может прослушивать только 127.0.0.1/::1. Эта функция рекомендует ограничить порты прослушивания публичной сети.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}如果限制本地后端端口，可能只能限制本机代理到后端的连接，不能代表真实公网来源。${PLAIN}" "${YELLOW}If you limit the local backend port, you may only be able to limit the connection from the local proxy to the backend, which cannot represent the real public source.${PLAIN}" "${YELLOW}Если вы ограничите локальный внутренний порт, вы сможете ограничить только подключение от локального прокси к серверной части, которая не может представлять собой реальный источник публичной сети.${PLAIN}")"
    fi
}

port_connlimit_rule_limits_for_port() {
    local cmd="$1"
    local port="$2"
    local comment
    comment=$(port_connlimit_comment "$port")

    "$cmd" -S INPUT 2>/dev/null | awk -v expected_comment="$comment" '
        $1 == "-A" && $2 == "INPUT" {
            matched = 0
            limit = ""
            for (i = 3; i <= NF; i++) {
                if ($i == "--comment" && i < NF) {
                    value = $(i + 1)
                    gsub(/^["\047]|["\047]$/, "", value)
                    if (value == expected_comment) {
                        matched = 1
                    }
                }
                if ($i == "--connlimit-above" && i < NF) {
                    limit = $(i + 1)
                }
            }
            if (matched && limit ~ /^[0-9]+$/) {
                print limit
            }
        }
    '
}

run_port_connlimit_rule_action() {
    local cmd="$1"
    local action="$2"
    local port="$3"
    local limit="$4"
    local mask="$5"
    local family_label="$6"
    local comment output existing_limits existing_count existing_limit keep_count remove_count i
    local changed=0 removed=0 cleanup_failed=0
    comment=$(port_connlimit_comment "$port")

    local args=(
        -p tcp --dport "$port" --syn
        -m connlimit --connlimit-above "$limit" --connlimit-mask "$mask" --connlimit-saddr
        -m comment --comment "$comment"
        -j REJECT --reject-with tcp-reset
    )

    case "$action" in
        add)
            existing_limits=$(port_connlimit_rule_limits_for_port "$cmd" "$port")
            keep_count=$(printf '%s\n' "$existing_limits" | grep -xc "$limit" || true)
            if (( keep_count == 0 )); then
                if output=$("$cmd" -I INPUT "${args[@]}" 2>&1); then
                    changed=1
                else
                    echo -e "$(localized_text "${RED}❌ ${family_label} 添加失败：${output}${PLAIN}" "${RED}❌ ${family_label} Failed to add: ${output}${PLAIN}" "${RED}❌ ${family_label} Не удалось добавить: ${output}${PLAIN}")"
                    return 1
                fi
            fi

            while read -r existing_count existing_limit; do
                [[ -n "$existing_count" && -n "$existing_limit" ]] || continue
                keep_count=0
                [[ "$existing_limit" == "$limit" ]] && keep_count=1
                remove_count=$((existing_count - keep_count))
                local cleanup_args=(
                    -p tcp --dport "$port" --syn
                    -m connlimit --connlimit-above "$existing_limit" --connlimit-mask "$mask" --connlimit-saddr
                    -m comment --comment "$comment"
                    -j REJECT --reject-with tcp-reset
                )
                for ((i = 0; i < remove_count; i++)); do
                    if output=$("$cmd" -D INPUT "${cleanup_args[@]}" 2>&1); then
                        removed=$((removed + 1))
                        changed=1
                    else
                        cleanup_failed=1
                        echo -e "$(localized_text "${RED}❌ ${family_label} 清理端口 ${port} 的旧限制 ${existing_limit} 失败：${output}${PLAIN}" "${RED}❌ ${family_label} Failed to clean up old limit ${existing_limit} on port ${port}: ${output}${PLAIN}" "${RED}❌ ${family_label} Не удалось очистить старое ограничение ${existing_limit} на порту ${port}: ${output}${PLAIN}")"
                        break
                    fi
                done
            done < <(printf '%s\n' "$existing_limits" | sed '/^$/d' | sort -n | uniq -c)

            if (( cleanup_failed != 0 )); then
                echo -e "$(localized_text "${YELLOW}⚠️ ${family_label} 目标规则已保留，但同端口旧规则可能仍会叠加生效。${PLAIN}" "${YELLOW}⚠️ ${family_label} The target rule is retained, but old rules on the same port may still apply cumulatively.${PLAIN}" "${YELLOW}⚠️ ${family_label} Целевое правило сохранено, но старые правила на том же порту могут продолжать действовать совместно.${PLAIN}")"
                return 1
            fi
            if (( changed == 0 )); then
                echo -e "$(localized_text "${BLUE}ℹ️ ${family_label} 已存在唯一目标规则：端口 ${port}，每来源 IP 最大并发 ${limit}。${PLAIN}" "${BLUE}ℹ️ ${family_label} The single target rule already exists: port ${port}, maximum concurrency per source IP ${limit}.${PLAIN}" "${BLUE}ℹ️ ${family_label} Единственное целевое правило уже существует: порт ${port}, максимальное количество одновременных подключений на IP-адрес источника — ${limit}.${PLAIN}")"
            else
                echo -e "$(localized_text "${GREEN}✅ ${family_label} 已应用：端口 ${port}，每来源 IP 最大并发 ${limit}；清理旧/重复规则 ${removed} 条。${PLAIN}" "${GREEN}✅ ${family_label} Applied: port ${port}, maximum concurrency per source IP ${limit}; removed ${removed} old/duplicate rules.${PLAIN}" "${GREEN}✅ ${family_label} Применено: порт ${port}, максимальное количество одновременных подключений на IP-адрес источника — ${limit}; удалено старых/повторяющихся правил: ${removed}.${PLAIN}")"
            fi
            return 0
            ;;
        delete)
            existing_limits=$(port_connlimit_rule_limits_for_port "$cmd" "$port")
            remove_count=$(printf '%s\n' "$existing_limits" | grep -xc "$limit" || true)
            if (( remove_count == 0 )); then
                echo -e "$(localized_text "${YELLOW}⚠️ ${family_label} 未找到匹配规则：端口 ${port}，连接数 ${limit}。${PLAIN}" "${YELLOW}⚠️ ${family_label} No matching rule found: port ${port}, connection number ${limit}.${PLAIN}" "${YELLOW}⚠️ ${family_label} Не найдено соответствующее правило: порт ${port}, номер подключения ${limit}.${PLAIN}")"
                return 1
            fi
            for ((i = 0; i < remove_count; i++)); do
                if output=$("$cmd" -D INPUT "${args[@]}" 2>&1); then
                    removed=$((removed + 1))
                else
                    echo -e "$(localized_text "${RED}❌ ${family_label} 删除失败：${output}${PLAIN}" "${RED}❌ ${family_label} Deletion failed: ${output}${PLAIN}" "${RED}❌ ${family_label} Не удалось удалить: ${output}${PLAIN}")"
                    return 1
                fi
            done
            echo -e "$(localized_text "${GREEN}✅ ${family_label} 已删除：端口 ${port}，连接数 ${limit}，共 ${removed} 条。${PLAIN}" "${GREEN}✅ ${family_label} Deleted: port ${port}, connection limit ${limit}, ${removed} rule(s) in total.${PLAIN}" "${GREEN}✅ ${family_label} Удалено: порт ${port}, ограничение подключений ${limit}, всего правил: ${removed}.${PLAIN}")"
            return 0
            ;;
        *)
            echo -e "$(localized_text "${RED}❌ 未知 connlimit 操作：${action}${PLAIN}" "${RED}❌ unknown connlimit operation: ${action}${PLAIN}" "${RED}❌ неизвестная операция connlimit: ${action}${PLAIN}")"
            return 1
            ;;
    esac
}

read_connlimit_port() {
    local __target="$1"
    local port

    read_trimmed port "$(localized_text "请输入要限制的端口号（1-65535，回车或 0 取消）: " "Please enter the port number to be restricted (1-65535, press Enter or 0 to cancel):" "Введите номер порта, который необходимо ограничить (1-65535, нажмите Enter или 0 для отмены):")"
    if [[ -z "$port" || "$port" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消端口并发连接限制操作。${PLAIN}" "${BLUE}The port concurrent connection restriction operation has been canceled.${PLAIN}" "${BLUE}Операция ограничения одновременных подключений к порту была отменена.${PLAIN}")"
        return 1
    fi
    if ! is_valid_port "$port"; then
        echo -e "$(localized_text "${RED}❌ 端口无效，必须是 1-65535。${PLAIN}" "${RED}❌ Invalid port, must be 1-65535.${PLAIN}" "${RED}❌ Неверный порт, должен быть 1-65535.${PLAIN}")"
        return 1
    fi

    printf -v "$__target" '%s' "$((10#$port))"
}

read_connlimit_limit() {
    local __target="$1"
    local limit

    read_trimmed limit "$(localized_text "请输入每个来源 IP 最大 TCP 并发连接数（正整数，回车或 0 取消）: " "Please enter the maximum number of TCP concurrent connections for each source IP (positive integer, press Enter or 0 to cancel):" "Введите максимальное количество одновременных подключений TCP для каждого IP-адреса источника (положительное целое число, нажмите Enter или 0 для отмены):")"
    if [[ -z "$limit" || "$limit" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消端口并发连接限制操作。${PLAIN}" "${BLUE}The port concurrent connection restriction operation has been canceled.${PLAIN}" "${BLUE}Операция ограничения одновременных подключений к порту была отменена.${PLAIN}")"
        return 1
    fi
    if ! is_valid_connlimit_value "$limit"; then
        echo -e "$(localized_text "${RED}❌ 连接数无效，必须是正整数。${PLAIN}" "${RED}❌ The number of connections is invalid and must be a positive integer.${PLAIN}" "${RED}❌ Недопустимое количество соединений и должно быть положительным целым числом.${PLAIN}")"
        return 1
    fi

    printf -v "$__target" '%s' "$((10#$limit))"
}

func_add_port_connlimit_rule() {
    local port limit apply_ipv6 rc=0 touched=0

    read_connlimit_port port || return 0
    read_connlimit_limit limit || return 0
    read_trimmed apply_ipv6 "$(localized_text "是否同时应用 IPv6？(Y/n，默认 y): " "Do you want to apply IPv6 at the same time? (Y/n, default y):" "Хотите ли вы одновременно применить IPv6? (Да/нет, по умолчанию y):")"

    print_port_connlimit_scope_notice "$port"
    echo -e "$(localized_text "${CYAN}即将添加规则标记：$(port_connlimit_comment "$port")${PLAIN}" "${CYAN}Will soon add rule tags: $(port_connlimit_comment \"$port\")${PLAIN}" "${CYAN}В скоро будут добавлены теги правил: $(port_connlimit_comment \"$port\").${PLAIN}")"

    ensure_connlimit_tool iptables "IPv4" || return 1
    if is_yes "$apply_ipv6"; then
        ensure_connlimit_tool ip6tables "IPv6" || return 1
    fi
    try_load_connlimit_module

    confirm_risk_action "$(localized_text "添加端口 ${port} 并发连接限制" "Add port ${port} concurrent connection limit" "Добавить лимит одновременных подключений порта ${port}")" \
        "$(localized_text "iptables/ip6tables INPUT 链 connlimit 规则，超过 ${limit} 条并发的新 TCP 连接将被拒绝" "iptables/ip6tables INPUT chain connlimit rule, new TCP connections exceeding ${limit} concurrent connections will be rejected" "Правило iptables/ip6tables INPUT для цепочки connlimit, новые подключения TCP, превышающие количество одновременных подключений ${limit}, будут отклонены.")" \
        "$(localized_text "回到本菜单按同一端口和连接数删除规则；必要时通过云控制台/VNC 清理 iptables 规则" "Return to this menu to delete rules by the same port and connection number; if necessary, clear the iptables rule through the cloud console/VNC" "Вернитесь в это меню, чтобы удалить правила по тому же порту и номеру подключения; при необходимости очистите правило iptables через облачную консоль/VNC.")" \
        "$(localized_text "该规则是额外连接数限制，不代表端口已被 UFW/firewalld 放行。" "This is an additional connection limit; it does not mean UFW/firewalld allows the port." "Это дополнительное ограничение соединений; оно не означает, что UFW/firewalld разрешает порт.")" || {
        echo -e "$(localized_text "${BLUE}已取消添加端口并发连接限制。${PLAIN}" "${BLUE}The added port concurrent connection limit has been cancelled.${PLAIN}" "${BLUE}Ограничение количества одновременных подключений к добавленному порту было отменено.${PLAIN}")"
        return 0
    }

    if run_port_connlimit_rule_action iptables add "$port" "$limit" 32 "IPv4"; then
        touched=1
    else
        rc=1
    fi
    if is_yes "$apply_ipv6"; then
        if run_port_connlimit_rule_action ip6tables add "$port" "$limit" 128 "IPv6"; then
            touched=1
        else
            rc=1
        fi
    fi
    if [[ "$touched" -eq 1 ]]; then
        auto_save_port_connlimit_persistence_after_change "$(localized_text "添加规则" "Add rule" "Добавить правило")" || true
    else
        echo -e "$(localized_text "${YELLOW}提示：添加未完全成功，未自动刷新持久化快照；请先处理上方失败项。${PLAIN}" "${YELLOW}Tip: The addition was not completely successful and the persistent snapshot was not automatically refreshed; please handle the above failure items first.${PLAIN}" "${YELLOW}Совет: добавление не было полностью успешным, и постоянный снимок не обновлялся автоматически; пожалуйста, сначала обработайте вышеуказанные неисправности.${PLAIN}")"
    fi
    return "$rc"
}

func_delete_port_connlimit_rule() {
    local port limit delete_ipv6 rc=0

    read_connlimit_port port || return 0
    read_connlimit_limit limit || return 0
    read_trimmed delete_ipv6 "$(localized_text "是否同时删除 IPv6 对应规则？(Y/n，默认 yes): " "Do you want to delete the rules corresponding to IPv6 at the same time? (Y/n, default yes):" "Вы хотите одновременно удалить правила, соответствующие IPv6? (Да/нет, по умолчанию да):")"

    print_port_connlimit_scope_notice "$port"
    echo -e "$(localized_text "${CYAN}将按端口和连接数精确删除规则标记：$(port_connlimit_comment "$port")${PLAIN}" "${CYAN}Will remove rule tags by port and connection number exactly: $(port_connlimit_comment \"$port\")${PLAIN}" "${CYAN}удалит теги правил точно по порту и номеру соединения: $(port_connlimit_comment \"$port\")${PLAIN}")"

    ensure_connlimit_tool iptables "IPv4" || return 1
    if ! is_no "$delete_ipv6"; then
        ensure_connlimit_tool ip6tables "IPv6" || return 1
    fi

    confirm_risk_action "$(localized_text "删除端口 ${port} 并发连接限制" "Delete port ${port} concurrent connection limit" "Удалить лимит одновременных подключений порта ${port}")" \
        "$(localized_text "仅删除端口 ${port}、连接数 ${limit}、脚本标记为 $(port_connlimit_comment "$port") 的 connlimit 规则" "Delete only the connlimit rules with port ${port}, connection number ${limit}, and script tag $(port_connlimit_comment \"$port\")" "Удалите только правила connlimit с портом ${port}, номером соединения ${limit} и тегом сценария $(port_connlimit_comment \"$port\").")" \
        "$(localized_text "如误删，可回到本菜单重新添加同端口同连接数限制" "If you delete it by mistake, you can return to this menu and re-add the limit on the number of the same port and the same connection." "Если вы удалили его по ошибке, то можете вернуться в это меню и заново добавить ограничение на количество того же порта и того же соединения.")" \
        "$(localized_text "本操作不会清空 UFW/firewalld，也不会批量清空 iptables。" "This operation will not clear UFW/firewalld, nor will it clear iptables in batches." "Эта операция не очистит UFW/firewalld и не очистит iptables в пакетном режиме.")" || {
        echo -e "$(localized_text "${BLUE}已取消删除端口并发连接限制。${PLAIN}" "${BLUE}The port concurrent connection limit has been canceled.${PLAIN}" "${BLUE}Ограничение на количество одновременных подключений к порту отменено.${PLAIN}")"
        return 0
    }

    run_port_connlimit_rule_action iptables delete "$port" "$limit" 32 "IPv4" || rc=1
    if ! is_no "$delete_ipv6"; then
        run_port_connlimit_rule_action ip6tables delete "$port" "$limit" 128 "IPv6" || rc=1
    fi
    auto_save_port_connlimit_persistence_after_change "$(localized_text "删除规则" "delete rule" "удалить правило")" || true
    return "$rc"
}

func_show_port_connlimit_rules() {
    local found=0

    echo -e "$(localized_text "${CYAN}当前由 VPS-Optimize 添加的端口并发连接限制规则：${PLAIN}" "${CYAN}The current port concurrent connection limit rule added by VPS-Optimize:${PLAIN}" "${CYAN}Текущее правило ограничения одновременных подключений к порту, добавленное VPS-Optimize:${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}标记格式：VPSO_CONN_LIMIT_PORT_<端口>${PLAIN}" "${YELLOW}Tag format: VPSO_CONN_LIMIT_PORT_<port>${PLAIN}" "${YELLOW}Формат тега : VPSO_CONN_LIMIT_PORT_<порт>${PLAIN}")"
    echo ""

    if command -v iptables >/dev/null 2>&1; then
        echo -e "${BOLD}IPv4:${PLAIN}"
        if iptables -S INPUT 2>/dev/null | grep -F 'VPSO_CONN_LIMIT_PORT_'; then
            found=1
        else
            echo "$(localized_text "  未发现 IPv4 脚本规则。" "IPv4 script rule not found." "Правило сценария IPv4 не найдено.")"
        fi
    else
        echo -e "$(localized_text "${YELLOW}IPv4: 未检测到 iptables。${PLAIN}" "${YELLOW}IPv4: iptables not detected.${PLAIN}" "${YELLOW}IPv4: iptables не обнаружен.${PLAIN}")"
    fi

    echo ""
    if command -v ip6tables >/dev/null 2>&1; then
        echo -e "${BOLD}IPv6:${PLAIN}"
        if ip6tables -S INPUT 2>/dev/null | grep -F 'VPSO_CONN_LIMIT_PORT_'; then
            found=1
        else
            echo "$(localized_text "  未发现 IPv6 脚本规则。" "IPv6 script rule not found." "Правило сценария IPv6 не найдено.")"
        fi
    else
        echo -e "$(localized_text "${YELLOW}IPv6: 未检测到 ip6tables。${PLAIN}" "${YELLOW}IPv6: ip6tables not detected.${PLAIN}" "${YELLOW}IPv6: ip6tables не обнаружен.${PLAIN}")"
    fi

    echo ""
    if [[ "$found" -eq 0 ]]; then
        echo -e "$(localized_text "${BLUE}当前没有检测到本脚本添加的 connlimit 规则。${PLAIN}" "${BLUE}Currently does not detect the connlimit rule added by this script.${PLAIN}" "${BLUE}в настоящее время не обнаруживает правило connlimit, добавленное этим сценарием.${PLAIN}")"
    fi
    echo -e "$(localized_text "${YELLOW}提示：这些规则是连接数限制，不等同于 UFW/firewalld 的端口放行规则。${PLAIN}" "${YELLOW}Tip: These rules are connection number limits and are not equivalent to the port allow rules of UFW/firewalld.${PLAIN}" "${YELLOW}Совет. Эти правила представляют собой ограничения на количество подключений и не эквивалентны правилам освобождения портов UFW/firewalld.${PLAIN}")"
    echo ""
    print_port_connlimit_persistence_status
}

func_show_port_current_connections() {
    local port rows

    read_connlimit_port port || return 0

    if ! command -v ss >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 ss，正在尝试安装 iproute2/iproute...${PLAIN}" "${YELLOW}⚠️ ss not detected, trying to install iproute2/iproute...${PLAIN}" "${YELLOW}⚠️ ss не обнаружен, пытаюсь установить iproute2/iproute...${PLAIN}")"
        install_pkg iproute2 || install_pkg iproute || true
    fi
    if ! command -v ss >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}❌ 未检测到 ss，无法查看当前连接情况。${PLAIN}" "${RED}❌ ss is not detected and the current connection status cannot be viewed.${PLAIN}" "${RED}❌ ss не обнаружен и текущий статус подключения просмотреть невозможно.${PLAIN}")"
        return 1
    fi

    print_port_connlimit_scope_notice "$port"
    echo -e "$(localized_text "${CYAN}端口 ${port} 当前 ESTABLISHED TCP 连接按来源 IP 统计：${PLAIN}" "${CYAN}Port ${port} Current ESTABLISHED TCP Connection by Source IP Statistics:${PLAIN}" "${CYAN}Порт ${port} Текущий УСТАНОВЛЕН TCP Соединение по IP-статистике источника:${PLAIN}")"
    rows=$(ss -Htan state established 2>/dev/null | awk -v port="$port" '
        function is_local_port(endpoint) {
            return endpoint ~ (":" port "$") || endpoint ~ ("\\]:" port "$")
        }
        function remote_ip(endpoint) {
            if (endpoint ~ /^\[/) {
                sub(/^\[/, "", endpoint)
                sub(/\]:[0-9]+$/, "", endpoint)
                return endpoint
            }
            sub(/:[0-9]+$/, "", endpoint)
            return endpoint
        }
        is_local_port($4) {
            print remote_ip($5)
        }
    ' | sort | uniq -c | sort -nr)

    if [[ -z "$rows" ]]; then
        echo "$(localized_text "  当前没有 ESTABLISHED 连接。" "There are currently no ESTABLISHED connections." "В настоящее время нет УСТАНОВЛЕННЫХ соединений.")"
    else
        printf '%s\n' "$rows" | awk '{count=$1; $1=""; sub(/^ /, ""); printf "  %-45s %s\n", $0, count}'
    fi
}

show_firewall_menu_help() {
    echo "$(localized_text "防火墙菜单用于放行、删除、查看或关闭系统防火墙规则。删除规则和关闭防火墙都必须输入 yes 确认，大小写均可。" "The firewall menu is used to release, delete, view or close system firewall rules. To delete rules and turn off the firewall, you must enter yes to confirm, in both upper and lower case letters." "Меню брандмауэра используется для освобождения, удаления, просмотра или закрытия правил системного брандмауэра. Чтобы удалить правила и отключить брандмауэр, для подтверждения необходимо ввести «да» как заглавными, так и строчными буквами.")"
    echo "$(localized_text "自动放行会生成最小权限计划，展示协议、监听地址、进程和 Docker 映射；回环监听不会放行，当前 SSH 端口不能排除。" "automatic allow rules will generate a minimum privilege plan, showing the protocol, listening address, process and Docker mapping; loopback listening will not be released, and the current SSH port cannot be excluded." "При автоматическом выпуске будет создан план минимальных привилегий, показывающий протокол, адрес прослушивания, процесс и сопоставление Docker; Loopback-прослушивание не будет активирован, и текущий порт SSH не может быть исключен.")"
    echo "$(localized_text "计划只代表当前公网监听和 Docker 发布端口，不能判断业务是否仍需对外开放；可按编号排除非必要规则，确认后才应用。" "The plan only represents the current public listening and Docker publishing ports, and cannot determine whether the business still needs to be open to the outside world; unnecessary rules can be excluded by number and applied after confirmation." "План представляет только текущий прослушивание публичной сети и порты публикации Docker и не может определить, нужно ли по-прежнему бизнесу быть открытым для внешнего мира; ненужные правила можно исключить по количеству и применить после подтверждения.")"
    echo "$(localized_text "Docker 映射可能绕过普通 UFW/firewalld 端口规则；排除计划项不会关闭容器映射，需要同时修改 Docker 发布地址或使用 Docker 安全管理。" "Docker mapping may bypass ordinary UFW/firewalld port rules; excluding plan items will not turn off container mapping, and you need to modify the Docker publishing address at the same time or use Docker security management." "Сопоставление Docker может обходить обычные правила порта UFW/firewalld; исключение элементов плана не приведет к отключению сопоставления контейнеров, и вам необходимо одновременно изменить адрес публикации Docker или использовать управление безопасностью Docker.")"
    echo "$(localized_text "手动添加默认只放行 TCP，可明确选择 udp 或 both。删除旧规则默认同时检查 TCP/UDP。" "Manually adding only TCP is allowed by default, you can explicitly select udp or both. Deleting old rules also checks TCP/UDP by default." "По умолчанию разрешено добавление только TCP вручную, вы можете явно выбрать udp или оба. При удалении старых правил также по умолчанию проверяется TCP/UDP.")"
    echo "$(localized_text "端口并发连接限制用于按公网端口限制每来源 IP 的 TCP 并发连接数，IPv4 使用 iptables connlimit，IPv6 使用 ip6tables connlimit。" "The port concurrent connection limit is used to limit the number of TCP concurrent connections per source IP by public port. IPv4 uses iptables connlimit, and IPv6 uses ip6tables connlimit." "Ограничение одновременных подключений к порту используется для ограничения количества одновременных подключений TCP на IP-адрес источника по порту публичной сети. IPv4 использует connlimit iptables, а IPv6 использует connlimit ip6tables.")"
    echo "$(localized_text "该限制是额外连接数限制规则，不等同于 UFW/firewalld 的端口放行规则；两者可能并存。" "This restriction is an additional connection limit rule and is not equivalent to the UFW/firewalld port access rule; the two may coexist." "Это ограничение является дополнительным правилом ограничения подключений и не эквивалентно правилу освобождения порта UFW/firewalld; они могут сосуществовать.")"
    echo "$(localized_text "添加/删除 connlimit 后会自动尝试刷新持久化快照；[5] 可手动检查或再次保存。系统不支持时会提示当前规则只在本次运行期生效。" "After adding/removing connlimit, it will automatically try to refresh the persistent snapshot; [5] it can be checked manually or saved again. If the system does not support it, it will prompt that the current rule will only take effect during this running period." "После добавления/удаления connlimit он автоматически попытается обновить постоянный снимок; [5] его можно проверить вручную или сохранить снова. Если система его не поддерживает, она предложит, что текущее правило вступит в силу только в течение этого периода работы.")"
    echo "$(localized_text "如果限制公网 443 且当前启用了 443 单入口/端口复用，限制粒度只能是整个公网 443，不能精准到某个入站、SNI、UUID 或用户。" "If public port 443 is restricted and 443 shared entry/port reuse is currently enabled, the restriction granularity can only be the entire public port 443, and cannot be precise to a specific inbound connection, SNI, UUID, or user." "Если публичный порт 443 ограничена и в настоящее время включено повторное использование одной записи/порта 443, степень детализации ограничения может охватывать только всю публичный порт 443 и не может быть точной для конкретного входящего подключения, SNI, UUID или пользователя.")"
}

func_port_connlimit_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "防火墙规则管理 > 端口并发连接限制" "Firewall Rule Management > Port Concurrent Connection Limit" "Управление правилами межсетевого экрана > Ограничение количества одновременных подключений к порту")"
        echo -e "$(localized_text "${BOLD}端口并发连接限制${PLAIN}" "${BOLD}Port concurrent connection limit${PLAIN}" "${BOLD}Ограничение количества одновременных подключений к порту${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}用途：按公网端口限制每来源 IP 的 TCP 并发连接数。${PLAIN}" "${YELLOW}Purpose: Limit the number of TCP concurrent connections per source IP based on the public port.${PLAIN}" "${YELLOW}Назначение: Ограничить количество одновременных подключений TCP на IP-адрес источника в зависимости от порта публичной сети.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}说明：这是额外 connlimit 规则，不等同于 UFW/firewalld 放行规则。${PLAIN}" "${YELLOW}Description: This is an additional connlimit rule, not equivalent to the UFW/firewalld allow access rule.${PLAIN}" "${YELLOW}Описание: Это дополнительное правило connlimit, которое не эквивалентно правилу выпуска UFW/firewalld.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}持久化：添加/删除后自动尝试保存；用 [5] 手动检查/重试。${PLAIN}" "${YELLOW}Persistence: Automatically try to save after adding/deleting; use [5] to manually check/retry.${PLAIN}" "${YELLOW}Постоянство: автоматически пытаться сохранить после добавления/удаления; используйте [5] для проверки/повторения вручную.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 添加端口并发连接限制${PLAIN}" "${GREEN}1. Add port concurrent connection limit${PLAIN}" "${GREEN}1. Добавьте ограничение на количество одновременных подключений к порту.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 删除端口并发连接限制${PLAIN}" "${GREEN}2. Delete the port concurrent connection limit${PLAIN}" "${GREEN}2. Удалите ограничение на количество одновременных подключений к порту.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 查看当前连接数限制规则${PLAIN}" "${GREEN}3. View the current connection limit rule${PLAIN}" "${GREEN}3. Просмотр текущего правила ограничения подключений.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 查看某端口当前连接情况${PLAIN}" "${GREEN}4. Check the current connection status of a port${PLAIN}" "${GREEN}4. Проверьте текущий статус подключения порта.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 保存/检查重启持久化${PLAIN}" "${GREEN}5. Save/check restart persistence${PLAIN}" "${GREEN}5. Сохранить/проверить сохранение перезапуска${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  0. 返回上一级${PLAIN}" "${BLUE}0. Return to the previous level${PLAIN}" "${BLUE}0. Возврат на предыдущий уровень.${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local connlimit_choice
        read_trimmed connlimit_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"
        case "$connlimit_choice" in
            1) func_add_port_connlimit_rule; pause_return ;;
            2) func_delete_port_connlimit_rule; pause_return ;;
            3) func_show_port_connlimit_rules; pause_return ;;
            4) func_show_port_current_connections; pause_return ;;
            5) func_save_port_connlimit_persistence; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效的选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

firewall_detect_public_listener_rules() {
    firewall_collect_public_listener_details | awk -F'|' '
        NF >= 2 {
            print $1 "/" $2
        }
    ' | sort -t/ -k1,1n -k2,2 -u
}

firewall_collect_public_listener_details() {
    local source_label
    source_label="$(localized_text "系统监听" "System listener" "Системный слушатель")"
    ss -H -lntup 2>/dev/null | awk -v source_label="$source_label" '
        $1 ~ /^(tcp|udp)/ {
            proto = ($1 ~ /^tcp/) ? "tcp" : "udp"
            endpoint = $5
            port = endpoint
            sub(/^.*:/, "", port)
            address = endpoint
            sub(/:[0-9]+$/, "", address)
            normalized = tolower(address)
            gsub(/^\[|\]$/, "", normalized)
            sub(/%.*/, "", normalized)
            if (normalized == "localhost" ||
                normalized ~ /^127\./ ||
                normalized == "::1" ||
                normalized ~ /^::ffff:127\./) {
                next
            }
            process = "-"
            details = ""
            for (i = 7; i <= NF; i++) {
                details = details (details ? " " : "") $i
            }
            if (match(details, /users:\(\("[^"]+"/)) {
                process = substr(details, RSTART, RLENGTH)
                sub(/^users:\(\("/, "", process)
                sub(/".*$/, "", process)
            }
            if (port ~ /^[0-9]+$/ && port >= 1 && port <= 65535) {
                print port "|" proto "|" address "|" process "|" source_label "|"
            }
        }
    '
}

firewall_is_loopback_address() {
    local address
    address=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
    address="${address#[}"
    address="${address%]}"
    address="${address%%%*}"
    [[ "$address" == "localhost" || "$address" == 127.* || "$address" == "::1" || "$address" == ::ffff:127.* ]]
}

firewall_collect_docker_listener_details() {
    command -v docker >/dev/null 2>&1 || return 0

    local container line container_port protocol binding host_address host_port
    while IFS= read -r container; do
        [[ -n "$container" ]] || continue
        while IFS= read -r line; do
            if [[ "$line" =~ ^([0-9]+)/(tcp|udp)[[:space:]]+-\>[[:space:]]+(.+):([0-9]+)$ ]]; then
                container_port="${BASH_REMATCH[1]}"
                protocol="${BASH_REMATCH[2]}"
                host_address="${BASH_REMATCH[3]}"
                host_port="${BASH_REMATCH[4]}"
                if ! firewall_is_loopback_address "$host_address" && is_valid_port "$host_port"; then
                    binding="${host_port} -> ${container_port}/${protocol}"
                    printf '%s|%s|%s|docker:%s|Docker|%s\n' \
                        "$host_port" "$protocol" "$host_address" "$container" "$binding"
                fi
            fi
        done < <(docker port "$container" 2>/dev/null || true)
    done < <(docker ps --format '{{.Names}}' 2>/dev/null || true)
}

firewall_add_unique_plan_value() {
    local current="$1"
    local value="$2"
    local item
    local -a current_items=()
    [[ -n "$value" && "$value" != "-" ]] || {
        printf '%s\n' "$current"
        return 0
    }
    IFS=';' read -ra current_items <<< "$current"
    for item in "${current_items[@]}"; do
        if [[ "$item" == "$value" ]]; then
            printf '%s\n' "$current"
            return 0
        fi
    done
    if [[ -n "$current" ]]; then
        printf '%s;%s\n' "$current" "$value"
    else
        printf '%s\n' "$value"
    fi
}

firewall_detect_ssh_port() {
    local ssh_port=""
    local -a ssh_connection_parts=()
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        read -ra ssh_connection_parts <<< "$SSH_CONNECTION"
        ssh_port="${ssh_connection_parts[3]:-}"
        is_valid_port "$ssh_port" || ssh_port=""
    fi
    if [[ -z "$ssh_port" ]]; then
        ssh_port=$(ss -H -tlnp 2>/dev/null | awk '
            /users:\(\("sshd"/ {
                port = $5
                sub(/^.*:/, "", port)
                if (port ~ /^[0-9]+$/) {
                    print port
                    exit
                }
            }
        ' || true)
    fi
    [[ -n "$ssh_port" ]] || ssh_port=$(awk 'tolower($1) == "port" { print $2; exit }' /etc/ssh/sshd_config 2>/dev/null || true)
    ssh_port="${ssh_port:-22}"
    is_valid_port "$ssh_port" || ssh_port=22
    printf '%s\n' "$ssh_port"
}

firewall_build_minimum_plan() {
    local ssh_port="${1:-}"
    local port protocol address process source mapping key
    local -A addresses=()
    local -A processes=()
    local -A sources=()
    local -A mappings=()
    local -A protected=()
    local -A seen=()
    local -a keys=()

    while IFS='|' read -r port protocol address process source mapping; do
        [[ -n "$port" && -n "$protocol" ]] || continue
        key="${port}/${protocol}"
        if [[ -z "${seen[$key]:-}" ]]; then
            keys+=("$key")
            seen["$key"]=1
            protected["$key"]="no"
        fi
        addresses["$key"]=$(firewall_add_unique_plan_value "${addresses[$key]:-}" "$address")
        processes["$key"]=$(firewall_add_unique_plan_value "${processes[$key]:-}" "$process")
        sources["$key"]=$(firewall_add_unique_plan_value "${sources[$key]:-}" "$source")
        mappings["$key"]=$(firewall_add_unique_plan_value "${mappings[$key]:-}" "$mapping")
    done < <(
        firewall_collect_public_listener_details
        firewall_collect_docker_listener_details
    )

    [[ -n "$ssh_port" ]] || ssh_port=$(firewall_detect_ssh_port 2>/dev/null || true)
    if is_valid_port "$ssh_port"; then
        key="${ssh_port}/tcp"
        if [[ -z "${seen[$key]:-}" ]]; then
            keys+=("$key")
            seen["$key"]=1
            addresses["$key"]="$(localized_text "按 SSH 配置保护" "Configure protection by SSH" "Настроить защиту по SSH")"
        fi
        processes["$key"]=$(firewall_add_unique_plan_value "${processes[$key]:-}" "sshd")
        sources["$key"]=$(firewall_add_unique_plan_value "${sources[$key]:-}" "$(localized_text "SSH 保护" "SSH Protection" "SSH Защита")")
        protected["$key"]="yes"
    fi

    for key in "${keys[@]}"; do
        port="${key%/*}"
        protocol="${key#*/}"
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "$port" "$protocol" "${addresses[$key]:--}" "${processes[$key]:--}" \
            "${sources[$key]:--}" "${mappings[$key]:--}" "${protected[$key]:-no}"
    done | sort -t'|' -k1,1n -k2,2
}

firewall_print_minimum_plan() {
    local plan="$1"
    local index=0 port protocol address process source mapping protected
    echo -e "$(localized_text "${CYAN}👇 最小权限防火墙计划：${PLAIN}" "${CYAN}👇 Least Privilege Firewall Plan:${PLAIN}" "${CYAN}👇 План брандмауэра с наименьшими привилегиями:${PLAIN}")"
    while IFS='|' read -r port protocol address process source mapping protected; do
        [[ -n "$port" ]] || continue
        index=$((index + 1))
        printf '  [%d] %s/%s\n' "$index" "$port" "$protocol"
        printf "$(localized_text '      监听地址: %s\n' 'Listening address: %s\n' 'Адрес прослушивания: %s\n')" "${address:--}"
        printf "$(localized_text '      进程: %s\n' 'Process: %s\n' 'Процесс: %s\n')" "${process:--}"
        printf "$(localized_text '      来源: %s\n' 'Source: %s\n' 'Источник: %s\n')" "${source:--}"
        printf "$(localized_text '      Docker 映射: %s\n' 'Docker mapping: %s\n' 'Сопоставление Docker: %s\n')" "${mapping:--}"
        if [[ "$protected" == "yes" ]]; then
            echo "$(localized_text "      保护: 当前 SSH 端口，不能排除" "Protection: Current SSH port, cannot be excluded" "Защита: текущий порт SSH, исключить нельзя.")"
        fi
    done <<< "$plan"
}

firewall_select_minimum_plan_rules() {
    local plan="$1"
    local exclusions="${2:-}"
    local count index item item_number port protocol address process source mapping protected
    local -A excluded=()
    local -a exclusion_items=()

    exclusions="${exclusions//[[:space:]]/}"
    count=$(grep -c '^[0-9]' <<< "$plan" || true)
    if [[ -n "$exclusions" ]]; then
        [[ "$exclusions" =~ ^[0-9]+(,[0-9]+)*$ ]] || {
            echo "$(localized_text "排除编号格式无效，请使用逗号分隔，例如：2,4。" "The exclusion number format is invalid, please use commas to separate them, for example: 2,4." "Неверный формат номера исключения. Разделяйте его запятыми, например: 2,4.")" >&2
            return 1
        }
        IFS=',' read -ra exclusion_items <<< "$exclusions"
        for item in "${exclusion_items[@]}"; do
            item_number=$((10#$item))
            if (( item_number < 1 || item_number > count )); then
                echo "$(localized_text "排除编号 ${item} 不在计划范围内。" "Exclusion number ${item} is not within the scope of the plan." "Номер исключения ${item} не входит в рамки плана.")" >&2
                return 1
            fi
            excluded["$item_number"]=1
        done
    fi

    index=0
    while IFS='|' read -r port protocol address process source mapping protected; do
        [[ -n "$port" ]] || continue
        index=$((index + 1))
        if [[ -n "${excluded[$index]:-}" && "$protected" == "yes" ]]; then
            echo "$(localized_text "编号 ${index} 是当前 SSH 端口，已强制保留。" "Number ${index} is the current SSH port, which has been forcibly reserved." "Номер ${index} — это текущий порт SSH, который был принудительно зарезервирован.")" >&2
        elif [[ -n "${excluded[$index]:-}" ]]; then
            continue
        fi
        printf '%s/%s\n' "$port" "$protocol"
    done <<< "$plan"
}

normalize_firewall_protocol() {
    local protocol
    protocol=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
    case "$protocol" in
        tcp|udp|both) printf '%s\n' "$protocol" ;;
        *) return 1 ;;
    esac
}

firewall_apply_port_rule() {
    local action="$1"
    local port_rule="$2"
    local protocol="$3"
    local output command_rc

    if [[ "$OS" =~ debian|ubuntu ]]; then
        port_rule="${port_rule//-/:}"
        if [[ "$action" == "add" ]]; then
            output=$(ufw allow "${port_rule}/${protocol}" 2>&1)
            command_rc=$?
        else
            output=$(ufw delete allow "${port_rule}/${protocol}" 2>&1)
            command_rc=$?
        fi
    else
        port_rule="${port_rule//:/-}"
        if [[ "${VPSO_FIREWALLD_OFFLINE_MODE:-0}" == "1" && "$action" == "add" ]]; then
            output=$(firewall-offline-cmd --add-port="${port_rule}/${protocol}" 2>&1)
            command_rc=$?
        elif [[ "$action" == "add" ]]; then
            output=$(firewall-cmd --permanent --add-port="${port_rule}/${protocol}" 2>&1)
            command_rc=$?
        else
            output=$(firewall-cmd --permanent --remove-port="${port_rule}/${protocol}" 2>&1)
            command_rc=$?
        fi
    fi
    if [[ "$command_rc" -ne 0 ]]; then
        echo -e "$(localized_text "${RED}❌ ${action} ${port_rule}/${protocol} 失败：${output:-未知错误}${PLAIN}" "${RED}❌ ${action} ${port_rule}/${protocol} Failure: ${output:-未知错误}${PLAIN}" "${RED}❌ ${action} ${port_rule}/${protocol} Ошибка: ${output:-未知错误}${PLAIN}")"
        return 1
    fi
}

firewall_apply_port_input() {
    local action="$1"
    local port_input="$2"
    local protocol="$3"
    local rc=0 port_rule current_protocol
    local protocols=()
    local port_rules=()

    if [[ "$protocol" == "both" ]]; then
        protocols=(tcp udp)
    else
        protocols=("$protocol")
    fi
    IFS=',' read -ra port_rules <<< "$port_input"
    for port_rule in "${port_rules[@]}"; do
        if [[ "$action" == "delete" && "$protocol" == "both" && "$OS" =~ debian|ubuntu ]]; then
            local legacy_port_rule="${port_rule//-/:}"
            if ufw delete allow "$legacy_port_rule" >/dev/null 2>&1; then
                continue
            fi
        fi
        for current_protocol in "${protocols[@]}"; do
            firewall_apply_port_rule "$action" "$port_rule" "$current_protocol" || rc=1
        done
    done
    return "$rc"
}

func_firewall_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "防火墙规则管理" "Firewall rule management" "Управление правилами брандмауэра")"
        echo -e "$(localized_text "${BOLD}🛡️ 防火墙规则管理${PLAIN}" "${BOLD}🛡️ Firewall rule management${PLAIN}" "${BOLD}🛡️ Управление правилами брандмауэра${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local fw_status
        local str_fw
        if [[ "$OS" =~ debian|ubuntu ]]; then
            fw_status=$(ufw status 2>/dev/null | grep -wi active)
        else
            fw_status=$(systemctl is-active firewalld 2>/dev/null)
        fi

        if [[ "$fw_status" == *"active"* ]]; then
            str_fw="$(localized_text "${GREEN}运行中${PLAIN}" "${GREEN}Running${PLAIN}" "${GREEN}работает${PLAIN}")"
        else
            str_fw="$(localized_text "${RED}已关闭 / 未配置${PLAIN}" "${RED}Is closed /  is not configured${PLAIN}" "${RED}закрыт /  не настроен${PLAIN}")"
        fi

        echo -e "$(localized_text "当前防火墙状态: [ $str_fw ]" "Current firewall status: [ $str_fw ]" "Текущий статус брандмауэра: [ $str_fw ]")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 查看防火墙放行列表${PLAIN}" "${GREEN}1. View the firewall release list${PLAIN}" "${GREEN}1. Просмотрите список выпусков брандмауэра .${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 启用防火墙 + 最小权限放行规划${PLAIN} ${YELLOW}(可预览/排除，不覆盖原有规则)${PLAIN}" "${GREEN}2. Enable firewall + least privilege release planning   (can be previewed/excluded, does not overwrite the original rules)${PLAIN}" "${GREEN}2. Включить брандмауэр + планирование выпуска с минимальными привилегиями   (можно просмотреть/исключить, не перезаписывает исходные правила)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 手动放行端口${PLAIN} ${YELLOW}(可选 TCP/UDP，支持批量/范围)${PLAIN}" "${GREEN}3. Manually allow access to port   (optional TCP/UDP, supports batch/range)${PLAIN}" "${GREEN}3. Порт ручного выпуска   (дополнительно TCP/UDP, поддерживает пакетный режим/диапазон)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 删除已放行端口${PLAIN} ${YELLOW}(可选 TCP/UDP，支持批量/范围)${PLAIN}" "${GREEN}4. Delete the released port   (optional TCP/UDP, supports batch/range)${PLAIN}" "${GREEN}4. Удалить освобожденный порт   (дополнительно TCP/UDP, поддерживает пакетный режим/диапазон)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 端口并发连接限制${PLAIN} ${YELLOW}(按每来源 IP 限制 TCP 并发)${PLAIN}" "${GREEN}5. Port concurrent connection limit   (TCP concurrency limit per source IP)${PLAIN}" "${GREEN}5. Ограничение одновременного подключения к порту   (ограничение одновременного доступа TCP для каждого IP-адреса источника)${PLAIN}")"
        echo -e "$(localized_text "${RED}  6. 关闭防火墙${PLAIN}" "${RED}6. Turn off the firewall${PLAIN}" "${RED}6. Отключаем брандмауэр${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${BLUE}  0. 返回上一级菜单 / q 返回${PLAIN}" "${BLUE}0. Return to the previous menu / q Return to${PLAIN}" "${BLUE}0. Возврат в предыдущее меню / q Возврат в${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local fw_choice
        read_trimmed fw_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"

        case $fw_choice in
            1)
                echo -e "$(localized_text "${CYAN}👇 当前防火墙规则列表：${PLAIN}" "${CYAN}👇 Current firewall rule list:${PLAIN}" "${CYAN}👇 Текущий список правил брандмауэра:${PLAIN}")"
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    ufw status numbered
                else
                    firewall-cmd --list-ports
                fi
                read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                ;;
            2)
                echo -e "$(localized_text "${CYAN}👉 正在检查公网监听、进程和 Docker 发布端口...${PLAIN}" "${CYAN}👉 Checking the public listening, process and Docker publishing port...${PLAIN}" "${CYAN}👉 Проверка прослушивания, обработки и порта публикации Docker в публичной сети...${PLAIN}")"
                local firewall_plan active_rules exclusions selection_cancelled
                firewall_plan=$(firewall_build_minimum_plan)

                if [[ -z "$firewall_plan" ]]; then
                    echo -e "$(localized_text "${RED}❌ 未能识别到需要放行的监听端口，已取消启用防火墙，避免误锁 SSH。${PLAIN}" "${RED}❌ The listening port that needs to be released cannot be identified, and the firewall has been deactivated to avoid accidentally locking SSH.${PLAIN}" "${RED}❌ Прослушивающий порт, который необходимо освободить, не может быть идентифицирован, а брандмауэр отключен, чтобы избежать случайной блокировки SSH.${PLAIN}")"
                    echo -e "$(localized_text "${YELLOW}请先确认 ss/iproute2 可用，或使用 [3] 手动添加 SSH 端口后再启用。${PLAIN}" "${YELLOW}Please confirm that ss/iproute2 is available, or use [3] to manually add the SSH port before enabling it.${PLAIN}" "${YELLOW}Подтвердите, что ss/iproute2 доступен, или используйте [3], чтобы вручную добавить порт SSH, прежде чем включать его.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi
                firewall_print_minimum_plan "$firewall_plan"
                echo -e "$(localized_text "${YELLOW}说明：计划仅依据当前公网监听和 Docker 发布端口，仍需由你判断业务是否需要公网访问。${PLAIN}" "${YELLOW}Note: The plan is only based on the current public listening and Docker publishing ports. It is still up to you to determine whether the business requires public access.${PLAIN}" "${YELLOW}Примечание. План основан только на текущем прослушивании публичной сети и портах публикации Docker. Вам по-прежнему решать, требуется ли бизнесу доступ к публичной сети.${PLAIN}")"
                if grep -Fq '|Docker|' <<< "$firewall_plan"; then
                    echo -e "$(localized_text "${RED}⚠️ Docker 映射可能绕过普通 UFW/firewalld 规则；从计划排除不会关闭容器映射。${PLAIN}" "${RED}⚠️ Docker mapping may bypass normal UFW/firewalld rules; exclusion from schedule does not close container mapping.${PLAIN}" "${RED}⚠️ Сопоставление Docker может обходить обычные правила UFW/firewalld; исключение из расписания не закрывает сопоставление контейнеров.${PLAIN}")"
                    echo -e "$(localized_text "${YELLOW}如需收口，请同时修改 Docker 发布地址，或使用 [11 Docker 安全管理]。${PLAIN}" "${YELLOW}If  needs to be closed, please modify the Docker publishing address at the same time, or use [11 Docker Security Management].${PLAIN}" "${YELLOW}Если  необходимо закрыть, одновременно измените адрес публикации Docker или используйте [11 Docker Управление безопасностью].${PLAIN}")"
                fi

                selection_cancelled=0
                while true; do
                    read_trimmed exclusions "$(localized_text "👉 输入要排除的编号（逗号分隔，直接回车全部保留，q 取消）: " "👉 Enter the numbers to be excluded (separate by commas, press Enter to keep all, q to cancel):" "👉 Введите номера, которые необходимо исключить (разделите запятыми, нажмите Enter, чтобы сохранить все, q для отмены):")"
                    if [[ "$exclusions" =~ ^[qQ]$ ]]; then
                        selection_cancelled=1
                        break
                    fi
                    if active_rules=$(firewall_select_minimum_plan_rules "$firewall_plan" "$exclusions"); then
                        break
                    fi
                done
                if [[ "$selection_cancelled" -eq 1 ]]; then
                    echo -e "$(localized_text "${BLUE}已取消启用防火墙。${PLAIN}" "${BLUE}The firewall has been deactivated.${PLAIN}" "${BLUE}Брандмауэр отключен.${PLAIN}")"
                    sleep 1
                    continue
                fi
                echo -e "$(localized_text "${CYAN}将放行：$(echo "$active_rules" | tr '\n' ' ')${PLAIN}" "${CYAN}Will allow: $(echo \"$active_rules\" | tr '\n' ' ')${PLAIN}" "${CYAN}Будут разрешены: $(echo \"$active_rules\" | tr '\n' ' ')${PLAIN}")"
                confirm_risk_action "$(localized_text "启用防火墙并应用最小权限放行计划" "Enable firewall and apply least privilege scheme" "Включите брандмауэр и примените схему с наименьшими привилегиями.")" \
                    "$(localized_text "系统防火墙默认入站策略，以及上方选中的 TCP/UDP 放行规则" "The system firewall default inbound connection policy, and the TCP/UDP allowed access rule selected above" "Политика входящего подключения по умолчанию системного брандмауэра и выбранное выше правило выпуска TCP/UDP.")" \
                    "$(localized_text "保持当前 SSH 会话，使用云厂商控制台/VNC 关闭防火墙或补回业务端口" "Keep the current SSH session and use the cloud vendor console/VNC to close the firewall or replace the service port" "Сохраните текущий сеанс SSH и используйте консоль облачного поставщика/VNC, чтобы закрыть брандмауэр или заменить сервисный порт.")" \
                    "$(localized_text "确认上方计划已覆盖当前 SSH 和所有必须公网访问的服务。" "Confirm that the above plan has covered the current SSH and all services that must be accessed through the public." "Подтвердите, что вышеуказанный план охватывает текущий SSH и все услуги, доступ к которым должен осуществляться через публичную сеть.")" || {
                    echo -e "$(localized_text "${BLUE}已取消启用防火墙。${PLAIN}" "${BLUE}The firewall has been deactivated.${PLAIN}" "${BLUE}Брандмауэр отключен.${PLAIN}")"
                    sleep 1
                    continue
                }

                local firewall_rc=0 rule_entry rule_port rule_protocol
                local firewalld_was_inactive=0
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    if ! install_pkg ufw || ! command -v ufw >/dev/null 2>&1; then
                        echo -e "$(localized_text "${RED}❌ UFW 安装失败，未启用防火墙。${PLAIN}" "${RED}❌ UFW installation failed, firewall is not enabled.${PLAIN}" "${RED}❌ Не удалось установить UFW, брандмауэр не включен.${PLAIN}")"
                        sleep 2
                        continue
                    fi
                    ufw default deny incoming >/dev/null 2>&1 || firewall_rc=1
                    ufw default allow outgoing >/dev/null 2>&1 || firewall_rc=1
                else
                    if ! install_pkg firewalld || ! command -v firewall-cmd >/dev/null 2>&1; then
                        echo -e "$(localized_text "${RED}❌ Firewalld 安装失败，未继续写入规则。${PLAIN}" "${RED}❌ Firewalld installation failed and rules writing was not continued.${PLAIN}" "${RED}❌ Не удалось установить Firewalld, и запись правил не была продолжена.${PLAIN}")"
                        sleep 2
                        continue
                    fi
                    if ! systemctl is-active --quiet firewalld; then
                        if ! command -v firewall-offline-cmd >/dev/null 2>&1; then
                            echo -e "$(localized_text "${RED}❌ 缺少 firewall-offline-cmd，无法在启动防火墙前安全写入 SSH 放行规则。${PLAIN}" "${RED}❌ Missing firewall-offline-cmd prevents safe writing of SSH allow access rules before starting the firewall.${PLAIN}" "${RED}❌ Отсутствует firewall-offline-cmd, правило выпуска SSH не может быть безопасно записано перед запуском брандмауэра.${PLAIN}")"
                            sleep 2
                            continue
                        fi
                        firewalld_was_inactive=1
                        VPSO_FIREWALLD_OFFLINE_MODE=1
                    fi
                fi
                while IFS= read -r rule_entry; do
                    [[ -n "$rule_entry" ]] || continue
                    rule_port="${rule_entry%/*}"
                    rule_protocol="${rule_entry#*/}"
                    firewall_apply_port_rule add "$rule_port" "$rule_protocol" || firewall_rc=1
                done <<< "$active_rules"
                unset VPSO_FIREWALLD_OFFLINE_MODE

                if [[ "$OS" =~ debian|ubuntu ]]; then
                    if [[ "$firewall_rc" -eq 0 ]]; then
                        ufw --force enable >/dev/null 2>&1 || firewall_rc=1
                        ufw status 2>/dev/null | grep -qi active || firewall_rc=1
                    fi
                elif [[ "$firewall_rc" -eq 0 ]]; then
                    if [[ "$firewalld_was_inactive" -eq 1 ]]; then
                        systemctl enable --now firewalld >/dev/null 2>&1 || firewall_rc=1
                        systemctl is-active --quiet firewalld || firewall_rc=1
                    else
                        firewall-cmd --reload >/dev/null 2>&1 || firewall_rc=1
                    fi
                fi

                if [[ "$firewall_rc" -ne 0 ]]; then
                    echo -e "$(localized_text "${RED}❌ 防火墙配置未完整成功，请根据上方失败规则修复后重试。${PLAIN}" "${RED}❌ The firewall configuration is not complete and successful. Please repair according to the failure rules above and try again.${PLAIN}" "${RED}❌ Конфигурация брандмауэра не завершена и не выполнена успешно. Пожалуйста, исправьте ошибки в соответствии с приведенными выше правилами и повторите попытку.${PLAIN}")"
                    echo -e "$(localized_text "${YELLOW}计划放行：$(echo "$active_rules" | tr '\n' ' ')${PLAIN}" "${YELLOW}Planned allow rules: $(echo \"$active_rules\" | tr '\n' ' ')${PLAIN}" "${YELLOW}Планируемые разрешения: $(echo \"$active_rules\" | tr '\n' ' ')${PLAIN}")"
                    sleep 3
                    continue
                fi
                echo -e "$(localized_text "${GREEN}✅ 防火墙已启用，已按实际监听协议放行：$(echo "$active_rules" | tr '\n' ' ')${PLAIN}" "${GREEN}✅ Firewall enabled; allowed active listeners by protocol: $(echo \"$active_rules\" | tr '\n' ' ')${PLAIN}" "${GREEN}✅ Брандмауэр включён; активные прослушиваемые порты разрешены по протоколам: $(echo \"$active_rules\" | tr '\n' ' ')${PLAIN}")"
                sleep 2
                ;;
            3)
                local add_p add_protocol
                echo -e "$(localized_text "${YELLOW}💡 支持格式：单端口(80)、多端口(80,443)、端口范围(8000:9000 或 8000-9000)${PLAIN}" "${YELLOW}💡 Supported formats: single port (80), multi-port (80,443), port range (8000:9000 or 8000-9000)${PLAIN}" "${YELLOW}💡 Поддерживаемые форматы: один порт (80), многопорт (80 443), диапазон портов (8000:9000 или 8000-9000)${PLAIN}")"
                read_trimmed add_p "$(localized_text "👉 请输入要放行的端口号: " "👉 Please enter the port number to be released:" "👉 Пожалуйста, введите номер порта, который нужно освободить:")"
                add_p=$(normalize_port_rule_input "$add_p")
                if [[ -z "$add_p" || "$add_p" == "0" ]]; then
                    echo -e "$(localized_text "${BLUE}已取消添加端口规则。${PLAIN}" "${BLUE}The port rule has been added.${PLAIN}" "${BLUE}Добавлено правило для порта.${PLAIN}")"
                    sleep 1
                    continue
                fi

                # 放宽正则，允许数字、逗号、冒号和减号
                if is_valid_port_rule_input "$add_p"; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        install_pkg ufw
                        if ! command -v ufw >/dev/null 2>&1; then
                            echo -e "$(localized_text "${RED}❌ 未检测到 ufw，无法写入规则。${PLAIN}" "${RED}❌ ufw not detected, rules cannot be written.${PLAIN}" "${RED}❌ ufw не обнаружен, правила записать невозможно.${PLAIN}")"
                            sleep 2
                            continue
                        fi
                        if ! ufw status 2>/dev/null | grep -qi active; then
                            echo -e "$(localized_text "${YELLOW}⚠️ UFW 当前未启用，本次只写入规则；需要启用时请回到 [1] 自动放行活动端口。${PLAIN}" "${YELLOW}⚠️ UFW is currently not enabled, only the rules are written this time; if you need to enable it, please return to [1] Automatically release active ports.${PLAIN}" "${YELLOW}⚠️ UFW на данный момент не включен, на этот раз пишутся только правила; если вам нужно включить его, вернитесь к [1] ​​Автоматически освобождать активные порты.${PLAIN}")"
                        fi
                    elif ! systemctl is-active --quiet firewalld 2>/dev/null; then
                        echo -e "$(localized_text "${RED}❌ Firewalld 未运行。为避免误关端口，请先使用 [2] 启用并自动放行当前活动端口。${PLAIN}" "${RED}❌ Firewalld is not running. To avoid accidentally closing the port, please use [2] to enable and automatically release the currently active port.${PLAIN}" "${RED}❌ Firewalld не запущен. Чтобы избежать случайного закрытия порта, используйте [2] для включения и автоматического освобождения текущего активного порта.${PLAIN}")"
                        sleep 2
                        continue
                    fi
                    read_trimmed add_protocol "$(localized_text "👉 请选择协议 tcp/udp/both（默认 tcp）: " "👉 Please select protocol tcp/udp/both (default tcp):" "👉 Пожалуйста, выберите протокол tcp/udp/both (по умолчанию tcp):")"
                    add_protocol=$(normalize_firewall_protocol "${add_protocol:-tcp}" 2>/dev/null || true)
                    if [[ -z "$add_protocol" ]]; then
                        echo -e "$(localized_text "${RED}❌ 协议只能是 tcp、udp 或 both。${PLAIN}" "${RED}❌ The protocol can only be tcp, udp or both.${PLAIN}" "${RED}❌ Протокол может быть только tcp, udp или оба.${PLAIN}")"
                        sleep 2
                        continue
                    fi
                    if firewall_apply_port_input add "$add_p" "$add_protocol" \
                        && { [[ "$OS" =~ debian|ubuntu ]] || firewall-cmd --reload >/dev/null 2>&1; }; then
                        echo -e "$(localized_text "${GREEN}✅ 端口规则 [${add_p}/${add_protocol}] 已添加至允许列表。${PLAIN}" "${GREEN}✅ Port rule [${add_p}/${add_protocol}] has been added to the allow list.${PLAIN}" "${GREEN}✅ Правило порта [${add_p}/${add_protocol}] добавлено в список разрешений.${PLAIN}")"
                    else
                        echo -e "$(localized_text "${RED}❌ 端口规则 [${add_p}/${add_protocol}] 未完整添加，请检查上方错误。${PLAIN}" "${RED}❌ Port rule [${add_p}/${add_protocol}] is not completely added, please check the error above.${PLAIN}" "${RED}❌ Правило порта [${add_p}/${add_protocol}] не добавлено полностью, проверьте ошибку выше.${PLAIN}")"
                    fi
                else
                    echo -e "$(localized_text "${RED}❌ 无效的端口格式！端口必须是 1-65535，范围起始值不能大于结束值。${PLAIN}" "${RED}❌ Invalid port format! The port must be 1-65535, and the range start value cannot be greater than the end value.${PLAIN}" "${RED}❌ Неверный формат порта! Порт должен иметь номер 1–65535, а начальное значение диапазона не может быть больше конечного значения.${PLAIN}")"
                fi
                sleep 2
                ;;
            4)
                local del_p del_protocol
                echo -e "$(localized_text "${YELLOW}💡 支持格式：单端口(80)、多端口(80,443)、端口范围(8000:9000 或 8000-9000)${PLAIN}" "${YELLOW}💡 Supported formats: single port (80), multi-port (80,443), port range (8000:9000 or 8000-9000)${PLAIN}" "${YELLOW}💡 Поддерживаемые форматы: один порт (80), многопорт (80 443), диапазон портов (8000:9000 или 8000-9000)${PLAIN}")"
                read_trimmed del_p "$(localized_text "👉 请输入要删除放行的端口号: " "👉 Please enter the port number to be deleted:" "👉 Пожалуйста, введите номер порта, который нужно удалить:")"
                del_p=$(normalize_port_rule_input "$del_p")
                if [[ -z "$del_p" || "$del_p" == "0" ]]; then
                    echo -e "$(localized_text "${BLUE}已取消删除端口规则。${PLAIN}" "${BLUE}The port rule has been canceled.${PLAIN}" "${BLUE}Правило порта отменено.${PLAIN}")"
                    sleep 1
                    continue
                fi

                if is_valid_port_rule_input "$del_p"; then
                    confirm_risk_action "$(localized_text "删除防火墙放行规则 ${del_p}" "Delete firewall permission rule ${del_p}" "Удалить правило разрешения брандмауэра ${del_p}")" \
                        "$(localized_text "系统防火墙端口放行规则" "System firewall port allow rules" "Правила выпуска портов системного брандмауэра")" \
                        "$(localized_text "重新进入防火墙菜单手动放行端口，或通过云厂商控制台/VNC 修复" "Re-enter the firewall menu to manually release the port, or repair it through the cloud vendor console/VNC" "Повторно войдите в меню брандмауэра, чтобы вручную освободить порт, или восстановите его через консоль поставщика облака/VNC.")" \
                        "$(localized_text "确认不会删除当前 SSH 端口或业务必需端口。" "Confirm that the current SSH port or business-required port will not be deleted." "Убедитесь, что текущий порт SSH или порт, необходимый для бизнеса, не будет удален.")" || {
                        echo -e "$(localized_text "${BLUE}已取消删除端口规则。${PLAIN}" "${BLUE}The port rule has been canceled.${PLAIN}" "${BLUE}Правило порта отменено.${PLAIN}")"
                        sleep 1
                        continue
                    }
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        install_pkg ufw
                        if ! command -v ufw >/dev/null 2>&1; then
                            echo -e "$(localized_text "${RED}❌ 未检测到 ufw，无法删除规则。${PLAIN}" "${RED}❌ ufw not detected, rule cannot be deleted.${PLAIN}" "${RED}❌ ufw не обнаружен, правило невозможно удалить.${PLAIN}")"
                            sleep 2
                            continue
                        fi
                    elif ! systemctl is-active --quiet firewalld 2>/dev/null; then
                        echo -e "$(localized_text "${RED}❌ Firewalld 未运行，无法读取/删除运行时规则。${PLAIN}" "${RED}❌ Firewalld is not running and cannot read/delete runtime rules.${PLAIN}" "${RED}❌ Firewalld не запущен и не может читать/удалять правила времени выполнения.${PLAIN}")"
                        sleep 2
                        continue
                    fi
                    read_trimmed del_protocol "$(localized_text "👉 请选择要删除的协议 tcp/udp/both（默认 both）: " "👉 Please select the protocol to delete tcp/udp/both (default both):" "👉 Пожалуйста, выберите протокол для удаления tcp/udp/both (оба по умолчанию):")"
                    del_protocol=$(normalize_firewall_protocol "${del_protocol:-both}" 2>/dev/null || true)
                    if [[ -z "$del_protocol" ]]; then
                        echo -e "$(localized_text "${RED}❌ 协议只能是 tcp、udp 或 both。${PLAIN}" "${RED}❌ The protocol can only be tcp, udp or both.${PLAIN}" "${RED}❌ Протокол может быть только tcp, udp или оба.${PLAIN}")"
                        sleep 2
                        continue
                    fi
                    if firewall_apply_port_input delete "$del_p" "$del_protocol" \
                        && { [[ "$OS" =~ debian|ubuntu ]] || firewall-cmd --reload >/dev/null 2>&1; }; then
                        echo -e "$(localized_text "${GREEN}✅ 端口规则 [${del_p}/${del_protocol}] 已从允许列表移除。${PLAIN}" "${GREEN}✅ Port rule [${del_p}/${del_protocol}] has been removed from the allowed list.${PLAIN}" "${GREEN}✅ Правило порта [${del_p}/${del_protocol}] удалено из списка разрешенных.${PLAIN}")"
                    else
                        echo -e "$(localized_text "${RED}❌ 端口规则 [${del_p}/${del_protocol}] 未完整移除，请检查上方错误。${PLAIN}" "${RED}❌ Port rule [${del_p}/${del_protocol}] was not completely removed, please check the error above.${PLAIN}" "${RED}❌ Правило порта [${del_p}/${del_protocol}] не было полностью удалено, проверьте ошибку выше.${PLAIN}")"
                    fi
                else
                    echo -e "$(localized_text "${RED}❌ 无效的端口格式！端口必须是 1-65535，范围起始值不能大于结束值。${PLAIN}" "${RED}❌ Invalid port format! The port must be 1-65535, and the range start value cannot be greater than the end value.${PLAIN}" "${RED}❌ Неверный формат порта! Порт должен иметь номер 1–65535, а начальное значение диапазона не может быть больше конечного значения.${PLAIN}")"
                fi
                sleep 2
                ;;
            5) func_port_connlimit_menu ;;
            6)
                confirm_risk_action "$(localized_text "关闭系统防火墙" "Turn off system firewall" "Отключить системный брандмауэр")" \
                    "$(localized_text "ufw/firewalld 服务状态和系统侧访问控制" "ufw/firewalld service status and system-side access control" "Статус службы ufw/firewalld и контроль доступа на стороне системы")" \
                    "$(localized_text "重新启用防火墙并恢复放行规则；必要时从云厂商安全组限制暴露面" "Re-enable the firewall and restore the permission rules; limit the exposure from the cloud vendor security group if necessary" "Снова включите брандмауэр и восстановите правила разрешений; при необходимости ограничить воздействие со стороны группы безопасности поставщика облачных услуг.")" \
                    "$(localized_text "确认关闭后不会暴露数据库、面板或内部服务。" "Verify that no databases, panels, or internal services will be exposed after shutdown." "Убедитесь, что после завершения работы никакие базы данных, панели или внутренние службы не будут доступны.")" || {
                    echo -e "$(localized_text "${BLUE}已取消关闭防火墙。${PLAIN}" "${BLUE}The firewall has been canceled.${PLAIN}" "${BLUE}Брандмауэр отменен.${PLAIN}")"
                    sleep 1
                    continue
                }
                echo -e "$(localized_text "${RED}⚠️ 正在关闭防火墙...${PLAIN}" "${RED}⚠️ Turning off the firewall...${PLAIN}" "${RED}⚠️ Отключение брандмауэра...${PLAIN}")"
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    if ufw disable >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi inactive; then
                        echo -e "$(localized_text "${GREEN}✅ 防火墙已禁用。${PLAIN}" "${GREEN}✅ Firewall is disabled.${PLAIN}" "${GREEN}✅ Брандмауэр отключен.${PLAIN}")"
                    else
                        echo -e "$(localized_text "${RED}❌ UFW 禁用失败或状态仍为 active。${PLAIN}" "${RED}❌ UFW disabling failed or the status is still active.${PLAIN}" "${RED}❌ Не удалось отключить UFW или статус все еще активен.${PLAIN}")"
                    fi
                else
                    if systemctl disable --now firewalld >/dev/null 2>&1 && ! systemctl is-active --quiet firewalld; then
                        echo -e "$(localized_text "${GREEN}✅ 防火墙已禁用。${PLAIN}" "${GREEN}✅ Firewall is disabled.${PLAIN}" "${GREEN}✅ Брандмауэр отключен.${PLAIN}")"
                    else
                        echo -e "$(localized_text "${RED}❌ Firewalld 禁用失败或服务仍在运行。${PLAIN}" "${RED}❌ Firewalld disabling failed or the service is still running.${PLAIN}" "${RED}❌ Не удалось отключить Firewalld или служба все еще работает.${PLAIN}")"
                    fi
                fi
                sleep 2
                ;;
            "?"|help) show_firewall_menu_help; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效的选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}
