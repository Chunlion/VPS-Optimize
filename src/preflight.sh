# shellcheck shell=bash
# Deployment preflight checks and issue diagnostic bundle generation.

preflight_install_missing_commands() {
    local missing=("$@")
    local pkgs=()
    local cmd

    for cmd in "${missing[@]}"; do
        case "$cmd" in
            curl) pkgs+=("curl") ;;
            wget) pkgs+=("wget") ;;
            sudo) pkgs+=("sudo") ;;
            ss)
                if is_debian; then
                    pkgs+=("iproute2")
                elif is_redhat; then
                    pkgs+=("iproute")
                fi
                ;;
        esac
    done

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        return 0
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在安装缺失基础命令: ${missing[*]}${PLAIN}" "${CYAN}▶ Installing missing basic command: ${missing[*]}${PLAIN}" "${CYAN}▶ Установка отсутствующей базовой команды: ${missing[*]}${PLAIN}")"
    install_pkg "${pkgs[@]}"
}

preflight_missing_minimal_compat_items() {
    local missing=()
    local cmd svc
    local commands=(sudo curl wget ss ip getent tar gzip openssl jq awk sed grep pgrep journalctl timedatectl git nano lsof)
    local services=()

    for cmd in "${commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("cmd:$cmd")
    done

    if is_debian; then
        services=(cron dbus chrony)
    elif is_redhat; then
        services=(crond dbus chronyd)
    fi

    for svc in "${services[@]}"; do
        systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | awk 'NF {found=1} END {exit found ? 0 : 1}' || missing+=("svc:$svc")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf '%s\n' "${missing[@]}"
    fi
}

preflight_enable_ntp() {
    local ntp_sync
    echo -e "$(localized_text "${CYAN}▶ 正在尝试开启系统 NTP 时间同步...${PLAIN}" "${CYAN}▶ Trying to enable system NTP time synchronization...${PLAIN}" "${CYAN}▶ Попытка включить системную синхронизацию времени NTP...${PLAIN}")"

    if is_debian; then
        install_pkg chrony
    elif is_redhat; then
        install_pkg chrony
    fi

    timedatectl set-ntp true >/dev/null 2>&1 || true
    systemctl enable --now chrony >/dev/null 2>&1 || true
    systemctl enable --now chronyd >/dev/null 2>&1 || true

    if command -v chronyc >/dev/null 2>&1; then
        chronyc -a 'burst 4/4' >/dev/null 2>&1 || true
        chronyc -a makestep >/dev/null 2>&1 || true
    else
        systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
    fi

    sleep 2
    ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [[ "$ntp_sync" == "yes" ]]; then
        echo -e "$(localized_text "${GREEN}✅ NTP 时间同步已恢复。${PLAIN}" "${GREEN}✅ NTP time synchronization has been restored.${PLAIN}" "${GREEN}✅ Синхронизация времени NTP восстановлена.${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}⚠️ NTP 仍未同步，下面是诊断信息：${PLAIN}" "${YELLOW}⚠️ NTP is still not synchronized, the following is the diagnostic information:${PLAIN}" "${YELLOW}⚠️ NTP по-прежнему не синхронизирован, следующая диагностическая информация:${PLAIN}")"
        timedatectl status 2>/dev/null || true
        chronyc tracking 2>/dev/null || true
        chronyc sources -v 2>/dev/null || true
        journalctl -u chrony -u chronyd -u systemd-timesyncd -n 20 --no-pager 2>/dev/null || true
    fi
}

func_preflight_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧪 一键运维预检 (网络/系统/资源/包管理/精简系统兼容)${PLAIN}" "${BOLD}🧪 One-click operation and maintenance preflight check (network/system/resources/package management/simplified system compatibility)${PLAIN}" "${BOLD}🧪 Предварительная проверка работы и обслуживания в один клик (сеть/система/ресурсы/управление пакетами/упрощенная совместимость системы)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local ok_count=0
    local warn_count=0
    local err_count=0

    echo -e "$(localized_text "${YELLOW}▶ [1/9] 检查系统运行状态...${PLAIN}" "${YELLOW}▶ [1/9] Check the system running status...${PLAIN}" "${YELLOW}▶ [1/9] Проверка рабочего состояния системы...${PLAIN}")"
    local sys_state
    sys_state=$(systemctl is-system-running 2>/dev/null)
    sys_state=${sys_state:-unknown}
    if [[ "$sys_state" == "running" ]]; then
        echo -e "$(localized_text "${GREEN}✅ systemd 状态正常: $sys_state${PLAIN}" "${GREEN}✅ systemd Normal status: $sys_state${PLAIN}" "${GREEN}✅ systemd Нормальный статус: $sys_state${PLAIN}")"
        ((ok_count++))
    elif [[ "$sys_state" == "degraded" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ systemd 状态降级: $sys_state${PLAIN}" "${YELLOW}⚠️ systemd status downgrade: $sys_state${PLAIN}" "${YELLOW}⚠️ Понижение статуса systemd: $sys_state${PLAIN}")"
        systemctl --failed --no-legend --no-pager 2>/dev/null | awk 'NF {print "   - " $1 " (" $2 ")"}' | head -n 8
        ((warn_count++))
    else
        echo -e "$(localized_text "${RED}❌ systemd 状态异常: $sys_state${PLAIN}" "${RED}❌ systemd Abnormal status: $sys_state${PLAIN}" "${RED}❌ systemd Ненормальное состояние: $sys_state${PLAIN}")"
        ((err_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [2/9] 检查公网连通性...${PLAIN}" "${YELLOW}▶ [2/9] Check public connectivity...${PLAIN}" "${YELLOW}▶ [2/9] Проверка подключения к публичной сети...${PLAIN}")"
    local ipv4
    ipv4=$(curl -s4 --max-time 3 icanhazip.com 2>/dev/null)
    if [[ -n "$ipv4" ]]; then
        echo -e "$(localized_text "${GREEN}✅ IPv4 连通正常: ${ipv4}${PLAIN}" "${GREEN}✅ IPv4 Connected normally: ${ipv4}${PLAIN}" "${GREEN}✅ IPv4 Подключено нормально: ${ipv4}${PLAIN}")"
        ((ok_count++))
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到公网 IPv4，可能为纯 IPv6 或网络受限${PLAIN}" "${YELLOW}⚠️ The public IPv4 is not detected, it may be pure IPv6 or network restricted${PLAIN}" "${YELLOW}⚠️ публичную сеть IPv4 не обнаружена, это может быть чистая IPv6 или ограниченная сеть.${PLAIN}")"
        ((warn_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [3/9] 检查 DNS 解析能力...${PLAIN}" "${YELLOW}▶ [3/9] Check the resolution ability of DNS...${PLAIN}" "${YELLOW}▶ [3/9] Проверьте разрешающую способность DNS...${PLAIN}")"
    if getent ahosts raw.githubusercontent.com >/dev/null 2>&1; then
        echo -e "$(localized_text "${GREEN}✅ DNS 解析正常 (raw.githubusercontent.com)${PLAIN}" "${GREEN}✅ DNS parses normally (raw.githubusercontent.com)${PLAIN}" "${GREEN}✅ DNS нормально анализирует (raw.githubusercontent.com)${PLAIN}")"
        ((ok_count++))
    else
        echo -e "$(localized_text "${RED}❌ DNS 解析失败，后续远程脚本可能无法下载${PLAIN}" "${RED}❌ DNS parsing failed, subsequent remote scripts may not be able to download${PLAIN}" "${RED}❌ Не удалось выполнить синтаксический анализ DNS, последующие удаленные сценарии не смогут загрузить.${PLAIN}")"
        ((err_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [4/9] 检查时间同步状态...${PLAIN}" "${YELLOW}▶ [4/9] Check time synchronization status...${PLAIN}" "${YELLOW}▶ [4/9] Проверка состояния синхронизации времени...${PLAIN}")"
    local ntp_sync
    local can_fix_ntp=false
    ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [[ "$ntp_sync" == "yes" ]]; then
        echo -e "$(localized_text "${GREEN}✅ NTP 时间同步正常${PLAIN}" "${GREEN}✅ NTP time synchronization is normal${PLAIN}" "${GREEN}✅ Синхронизация времени NTP в норме${PLAIN}")"
        ((ok_count++))
    else
        echo -e "$(localized_text "${YELLOW}⚠️ NTP 未同步，可能影响证书签发与仓库校验${PLAIN}" "${YELLOW}⚠️ NTP is not synchronized, which may affect certificate issuance and warehouse verification${PLAIN}" "${YELLOW}⚠️ NTP не синхронизирован, что может повлиять на выдачу сертификата и проверку склада${PLAIN}")"
        can_fix_ntp=true
        ((warn_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [5/9] 检查磁盘空间...${PLAIN}" "${YELLOW}▶ [5/9] Check disk space...${PLAIN}" "${YELLOW}▶ [5/9] Проверка места на диске...${PLAIN}")"
    local root_use
    root_use=$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}')
    if [[ -n "$root_use" && "$root_use" -lt 80 ]]; then
        echo -e "$(localized_text "${GREEN}✅ 根分区使用率健康: ${root_use}%${PLAIN}" "${GREEN}✅ Root partition usage is healthy: ${root_use}%${PLAIN}" "${GREEN}✅ Корневой раздел используется нормально: ${root_use}%${PLAIN}")"
        ((ok_count++))
    elif [[ -n "$root_use" && "$root_use" -lt 90 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 根分区使用率偏高: ${root_use}%${PLAIN}" "${YELLOW}⚠️ The root partition usage is high: ${root_use}%${PLAIN}" "${YELLOW}⚠️ Высокое использование корневого раздела: ${root_use}%${PLAIN}")"
        ((warn_count++))
    else
        echo -e "$(localized_text "${RED}❌ 根分区使用率危险: ${root_use:-未知}%${PLAIN}" "${RED}❌ Dangerous root partition usage: ${root_use:-未知}%${PLAIN}" "${RED}❌ Опасное использование корневого раздела: ${root_use:-未知}%${PLAIN}")"
        ((err_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [6/9] 检查可用内存...${PLAIN}" "${YELLOW}▶ [6/9] Check available memory...${PLAIN}" "${YELLOW}▶ [6/9] Проверка доступной памяти...${PLAIN}")"
    local mem_avail
    mem_avail=$(free -m | awk '/^Mem:/ {print $7}')
    [[ -z "$mem_avail" ]] && mem_avail=$(free -m | awk '/^Mem:/ {print $4}')
    if [[ -n "$mem_avail" && "$mem_avail" -ge 300 ]]; then
        echo -e "$(localized_text "${GREEN}✅ 可用内存充足: ${mem_avail}MB${PLAIN}" "${GREEN}✅ Sufficient available memory: ${mem_avail}MB${PLAIN}" "${GREEN}✅ Достаточно доступной памяти: ${mem_avail}MB${PLAIN}")"
        ((ok_count++))
    elif [[ -n "$mem_avail" && "$mem_avail" -ge 150 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 可用内存偏低: ${mem_avail}MB${PLAIN}" "${YELLOW}⚠️ Available memory is low: ${mem_avail}MB${PLAIN}" "${YELLOW}⚠️ Недостаточно доступной памяти: ${mem_avail}MB${PLAIN}")"
        ((warn_count++))
    else
        echo -e "$(localized_text "${RED}❌ 可用内存过低: ${mem_avail:-未知}MB${PLAIN}" "${RED}❌ Available memory is too low: ${mem_avail:-未知}MB${PLAIN}" "${RED}❌ Недостаточно доступной памяти: ${mem_avail:-未知}MB${PLAIN}")"
        ((err_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [7/9] 检查包管理器占用...${PLAIN}" "${YELLOW}▶ [7/9] Check package manager usage...${PLAIN}" "${YELLOW}▶ [7/9] Проверка использования менеджера пакетов...${PLAIN}")"
    local pkg_busy=false
    if is_debian; then
        pgrep -x apt >/dev/null 2>&1 && pkg_busy=true
        pgrep -x apt-get >/dev/null 2>&1 && pkg_busy=true
        pgrep -x dpkg >/dev/null 2>&1 && pkg_busy=true
    elif is_redhat; then
        pgrep -x yum >/dev/null 2>&1 && pkg_busy=true
        pgrep -x dnf >/dev/null 2>&1 && pkg_busy=true
        pgrep -x rpm >/dev/null 2>&1 && pkg_busy=true
    fi

    if $pkg_busy; then
        echo -e "$(localized_text "${YELLOW}⚠️ 检测到包管理器正在运行，建议稍后再安装软件${PLAIN}" "${YELLOW}⚠️ Detected that the package manager is running. It is recommended to install the software later.${PLAIN}" "${YELLOW}⚠️ Обнаружено, что менеджер пакетов запущен. Программное обеспечение рекомендуется установить позже.${PLAIN}")"
        ((warn_count++))
    else
        echo -e "$(localized_text "${GREEN}✅ 包管理器空闲，可安全执行安装任务${PLAIN}" "${GREEN}✅ The package manager is idle and can safely perform installation tasks${PLAIN}" "${GREEN}✅ Менеджер пакетов простаивает и может безопасно выполнять задачи установки${PLAIN}")"
        ((ok_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [8/9] 检查关键命令可用性...${PLAIN}" "${YELLOW}▶ [8/9] Check key command availability...${PLAIN}" "${YELLOW}▶ [8/9] Проверка доступности клавишных команд...${PLAIN}")"
    local cmd_miss=()
    command -v curl >/dev/null 2>&1 || cmd_miss+=("curl")
    command -v wget >/dev/null 2>&1 || cmd_miss+=("wget")
    command -v sudo >/dev/null 2>&1 || cmd_miss+=("sudo")
    command -v ss >/dev/null 2>&1 || cmd_miss+=("ss")
    if [[ ${#cmd_miss[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${GREEN}✅ 关键命令齐全${PLAIN}" "${GREEN}✅ Complete key commands${PLAIN}" "${GREEN}✅ Полные ключевые команды${PLAIN}")"
        ((ok_count++))
    else
        echo -e "$(localized_text "${RED}❌ 缺少关键命令: ${cmd_miss[*]}${PLAIN}" "${RED}❌ Missing key command: ${cmd_miss[*]}${PLAIN}" "${RED}❌ Отсутствует ключевая команда: ${cmd_miss[*]}.${PLAIN}")"
        ((err_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [9/9] 检查精简系统兼容组件...${PLAIN}" "${YELLOW}▶ [9/9] Check the streamlined system compatible components...${PLAIN}" "${YELLOW}▶ [9/9] Проверьте компоненты, совместимые с оптимизированной системой...${PLAIN}")"
    local minimal_miss=()
    mapfile -t minimal_miss < <(preflight_missing_minimal_compat_items)
    if [[ ${#minimal_miss[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${GREEN}✅ 精简系统兼容组件齐全${PLAIN}" "${GREEN}✅ Streamlined system with complete compatible components${PLAIN}" "${GREEN}✅ Оптимизированная система с полностью совместимыми компонентами${PLAIN}")"
        ((ok_count++))
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 检测到精简系统缺少组件/服务:${PLAIN}" "${YELLOW}⚠️ Detected that the streamlined system is missing components/services:${PLAIN}" "${YELLOW}⚠️ Обнаружено, что в оптимизированной системе отсутствуют компоненты/службы:.${PLAIN}")"
        printf '  - %s\n' "${minimal_miss[@]}"
        ((warn_count++))
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${CYAN}📌 预检汇总: ${GREEN}${ok_count} 正常${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${err_count} 异常${PLAIN}" "${CYAN}📌 preflight check summary: ${ok_count} Normal / ${warn_count} Warning / ${err_count} Abnormal${PLAIN}" "${CYAN}📌 Сводка предварительной проверки: ${ok_count} Нормально / ${warn_count} Предупреждение / ${err_count} Ненормально${PLAIN}")"
    if [[ "$err_count" -gt 0 ]]; then
        echo -e "$(localized_text "${RED}⚠️ 建议先修复异常项，再进行环境部署和系统改造。${PLAIN}" "${RED}⚠️ It is recommended to fix the abnormal items first, and then proceed with environment deployment and system modification.${PLAIN}" "${RED}⚠️ Рекомендуется сначала исправить аномальные элементы, а затем приступить к развертыванию среды и модификации системы.${PLAIN}")"
    elif [[ "$warn_count" -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}💡 当前可继续操作，但建议先处理警告项以提升稳定性。${PLAIN}" "${YELLOW}💡 You can currently continue to operate, but it is recommended to deal with the warning items first to improve stability.${PLAIN}" "${YELLOW}💡 В настоящее время вы можете продолжать работу, но рекомендуется сначала разобраться с предупреждающими элементами для повышения стабильности.${PLAIN}")"
    else
        echo -e "$(localized_text "${GREEN}🎉 当前环境健康，可直接进行后续部署。${PLAIN}" "${GREEN}🎉 The current environment is healthy and subsequent deployment can be carried out directly.${PLAIN}" "${GREEN}🎉 Текущая среда работоспособна, и последующее развертывание можно выполнить напрямую.${PLAIN}")"
    fi

    if ! $pkg_busy && { $can_fix_ntp || [[ ${#cmd_miss[@]} -gt 0 ]] || [[ ${#minimal_miss[@]} -gt 0 ]]; }; then
        local rerun_confirm
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${CYAN}🛠️ 可自动处理的简单问题:${PLAIN}" "${CYAN}🛠️ Simple questions that can be automatically handled:${PLAIN}" "${CYAN}🛠️ Простые вопросы, которые можно обрабатывать автоматически:${PLAIN}")"
        $can_fix_ntp && echo -e "$(localized_text "  - 开启 NTP 时间同步" "- Enable NTP time synchronization" "- Включить синхронизацию времени NTP")"
        [[ ${#cmd_miss[@]} -gt 0 ]] && echo -e "$(localized_text "  - 安装缺失基础命令: ${cmd_miss[*]}" "- Installation missing basic command: ${cmd_miss[*]}" "- При установке отсутствует базовая команда: ${cmd_miss[*]}.")"
        [[ ${#minimal_miss[@]} -gt 0 ]] && echo -e "$(localized_text "  - 补齐精简系统兼容组件" "- Completed streamlined system compatible components" "- Завершены оптимизированные компоненты, совместимые с системой.")"
        if confirm_danger "$(localized_text "自动修复预检问题" "Automatically fix preflight issues" "Автоматически исправить проблемы предварительной проверки")" \
            "$(localized_text "可能安装基础软件包并启用 NTP 时间同步" "may install base packages and enable NTP time synchronization" "может установить базовые пакеты и включить синхронизацию времени NTP")" \
            "$(localized_text "软件包变更需按系统包管理器回退；NTP 可在系统服务中关闭" "revert package changes with the system package manager; disable NTP through the system service" "изменения пакетов отменяются через системный менеджер пакетов; NTP можно отключить в системной службе")"; then
            [[ ${#minimal_miss[@]} -gt 0 ]] && ensure_minimal_system_compat
            $can_fix_ntp && preflight_enable_ntp
            [[ ${#cmd_miss[@]} -gt 0 ]] && preflight_install_missing_commands "${cmd_miss[@]}"
            echo -e "$(localized_text "${GREEN}✅ 简单修复已执行。${PLAIN}" "${GREEN}✅ Simple fix has been performed.${PLAIN}" "${GREEN}Выполнено простое исправление.${PLAIN}")"
            read_trimmed rerun_confirm "$(localized_text "是否立即重新体检？(Y/n): " "Do you want to re-examine immediately? (Y/n):" "Хотите немедленно пройти повторное обследование? (Да/Нет):")"
            if is_yes "$rerun_confirm"; then
                func_preflight_check
                return $?
            fi
        fi
    elif $pkg_busy; then
        echo -e "$(localized_text "${YELLOW}ℹ️ 包管理器正在运行，本次跳过自动安装类修复。${PLAIN}" "${YELLOW}ℹ️ The package manager is running, and the automatic installation repair will be skipped this time.${PLAIN}" "${YELLOW}ℹ️ Менеджер пакетов запущен, и автоматическое восстановление установки на этот раз будет пропущено.${PLAIN}")"
    fi

    if [[ "${VPSO_BEGINNER_FLOW:-0}" != "1" ]]; then
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
    fi
    if [[ "$err_count" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------
# 21. 配置备份与回滚中心
# ---------------------------------------------------------







# ---------------------------------------------------------
# 22. 服务健康总览
# ---------------------------------------------------------
service_state_for_issue() {
    local svc="$1"
    if service_unit_exists "$svc"; then
        if systemctl is-active --quiet "$svc"; then
            echo "$(localized_text "运行中" "Running" "Бег")"
        else
            echo "$(localized_text "已安装/未运行" "Installed/not running" "Установлено/не запущено")"
        fi
    else
        echo "$(localized_text "未检测到" "not detected" "не обнаружено")"
    fi
}

recent_journal_for_issue() {
    local svc="$1"
    if service_unit_exists "$svc"; then
        journalctl -u "$svc" -n 8 --no-pager 2>/dev/null | redact_sensitive_output
    else
        echo "$(localized_text "未检测到 ${svc} 服务" "${svc} service not detected" "Служба ${svc} не обнаружена")"
    fi
}

print_443_issue_connlimit_summary() {
    local marker runtime_rules saved_rules rules locations rule_count

    if ! declare -F port_connlimit_comment >/dev/null || ! declare -F port_connlimit_runtime_rule_fingerprints >/dev/null || ! declare -F port_connlimit_known_saved_rule_fingerprints >/dev/null; then
        echo "$(localized_text "- 443 connlimit: 未接入检测 helper" "- 443 connlimit: Not connected to detection helper" "- 443 connlimit: не подключен к помощнику обнаружения.")"
        return 0
    fi

    marker=$(port_connlimit_comment 443)
    runtime_rules=$(port_connlimit_runtime_rule_fingerprints | grep -E "${marker}([^0-9]|$)" || true)
    saved_rules=$(port_connlimit_known_saved_rule_fingerprints | grep -E "${marker}([^0-9]|$)" || true)
    rules=$(printf '%s\n%s\n' "$runtime_rules" "$saved_rules" | grep -E "${marker}([^0-9]|$)" || true)

    if [[ -z "$rules" ]]; then
        echo "$(localized_text "- 443 connlimit: 未检测到本脚本添加的公网 443 规则" "- 443 connlimit: The public port 443 rule added by this script was not detected" "- 443 connlimit: правило 443 публичной сети, добавленное этим скриптом, не обнаружено.")"
        return 0
    fi

    locations=""
    [[ -n "$runtime_rules" ]] && locations="$(localized_text "运行时" "runtime" "время выполнения")"
    [[ -n "$saved_rules" ]] && locations="$(localized_text "${locations:+${locations},}持久化文件" "${locations:+${locations},}persistent files" "${locations:+${locations},}постоянные файлы")"
    rule_count=$(printf '%s\n' "$rules" | grep -c . || true)

    echo "$(localized_text "- 443 connlimit: 检测到本脚本添加的公网 443 connlimit 规则 (${marker})" "- 443 connlimit: The public port 443 connlimit rule added by this script is detected (${marker})" "- 443 connlimit: обнаружено правило 443 connlimit публичной сети, добавленное этим сценарием (${marker}).")"
    echo "$(localized_text "  位置: ${locations:-未知}; 匹配条数: ${rule_count}" "Position: ${locations:-未知}; Number of matches: ${rule_count}" "Должность: ${locations:-未知}; Количество совпадений: ${rule_count}")"
    echo "$(localized_text "  提示: 该规则影响整个公网 443 入口，不能精确到某个 SNI、Xray/3x-ui 入站、UUID 或用户" "Tip: This rule affects the entire public port 443 entry and cannot be precise to a certain SNI, Xray/3x-ui inbound, UUID or user" "Совет: это правило влияет на всю запись 443 публичной сети и не может быть точным для определенного входящего SNI, Xray/3x-ui, UUID или пользователя.")"
}

print_443_single_entry_issue_summary() {
    local env_file="/etc/vps-optimize/sni-stack.env"
    local web_backend web_label xray_backend panel_backend sub_backend listener_consistency

    echo "$(localized_text "443端口复用摘要:" "Port 443 Reuse summary:" "Сводка по повторному использованию порта 443:")"
    if ! load_sni_stack_env >/dev/null 2>&1; then
        detect_current_entry_status
        echo "$(localized_text "- 配置文件: 未检测到 ${env_file}" "- Profile: ${env_file} not detected" "- Профиль: ${env_file} не обнаружен.")"
        echo "- ENTRY_MODE: ${ENTRY_STATUS_MODE:-not-configured}"
        echo "$(localized_text "- 公网 443 监听归属: ${ENTRY_STATUS_LISTENER_DISPLAY:-未知} (${ENTRY_STATUS_LISTENER_PROCESS:-unknown})" "- public port 443 listener: ${ENTRY_STATUS_LISTENER_DISPLAY:-未知} (${ENTRY_STATUS_LISTENER_PROCESS:-unknown})" "- Атрибуция прослушивания публичного порта 443: ${ENTRY_STATUS_LISTENER_DISPLAY:-未知} (${ENTRY_STATUS_LISTENER_PROCESS:-unknown})")"
        print_443_issue_connlimit_summary
        return 0
    fi

    detect_current_entry_status
    web_backend=$(web_proxy_backend)
    web_label=$(web_proxy_engine_label)
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    panel_backend=$(format_hostport "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT")
    sub_backend=$(format_hostport "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT")
    if [[ "$ENTRY_STATUS_CONSISTENT" == "yes" ]]; then
        listener_consistency="$(localized_text "一致" "consistent" "последовательный")"
    else
        listener_consistency="$(localized_text "不一致" "inconsistent" "непоследовательный")"
    fi

    echo "$(localized_text "- 配置文件: ${env_file}" "- Configuration file: ${env_file}" "- Файл конфигурации: ${env_file}.")"
    echo "- ENTRY_MODE: ${ENTRY_STATUS_MODE}"
    echo "$(localized_text "- 公网 443 监听归属: ${ENTRY_STATUS_LISTENER_DISPLAY} (${ENTRY_STATUS_LISTENER_PROCESS}); 与 ENTRY_MODE ${listener_consistency}" "- public port 443 listener: ${ENTRY_STATUS_LISTENER_DISPLAY} (${ENTRY_STATUS_LISTENER_PROCESS}); and ENTRY_MODE ${listener_consistency}" "- Атрибуция прослушивания публичного порта 443: ${ENTRY_STATUS_LISTENER_DISPLAY} (${ENTRY_STATUS_LISTENER_PROCESS}); и ENTRY_MODE ${listener_consistency}")"
    echo "$(localized_text "- Caddy/Web 本地后端: ${web_label} ${web_backend}" "- Caddy/Web local backend: ${web_label} ${web_backend}" "- Caddy/локальный веб-сервер: ${web_label} ${web_backend}")"
    echo "$(localized_text "- Xray 本地后端: ${xray_backend}" "- Xray local backend: ${xray_backend}" "- Локальный сервер Xray: ${xray_backend}")"
    echo "$(localized_text "- 面板路径: https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${panel_backend}" "-Panel path: https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${panel_backend}" "-Путь к панели: https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${panel_backend}")"
    echo "$(localized_text "- 订阅路径: 普通 ${SUB_URI_PATH}, Clash/Mihomo ${CLASH_URI_PATH} -> ${sub_backend}" "- Subscription path: Normal ${SUB_URI_PATH}, Clash/Mihomo ${CLASH_URI_PATH} -> ${sub_backend}" "- Путь подписки: Обычный ${SUB_URI_PATH}, Clash/Mihomo ${CLASH_URI_PATH} -> ${sub_backend}.")"
    echo "$(localized_text "- 扩展路由: Web ${#SITE_DOMAINS[@]} 个, TCP/SNI ${#TCP_ROUTE_SNIS[@]} 个, Xray 入站 ${#XRAY_SNI_ROUTE_SNIS[@]} 个" "- Extended routing: Web ${#SITE_DOMAINS[@]}, TCP/SNI ${#TCP_ROUTE_SNIS[@]}, Xray inbound ${#XRAY_SNI_ROUTE_SNIS[@]}" "- Расширенная маршрутизация: Web ${#SITE_DOMAINS[@]}, TCP/SNI ${#TCP_ROUTE_SNIS[@]}, Xray, входящая ${#XRAY_SNI_ROUTE_SNIS[@]}.")"
    print_443_issue_connlimit_summary
}

generate_issue_diagnostics() {
    local os_desc kernel arch now script_path firewall_status latest_backups log_path
    os_desc="$(localized_text "未知" "unknown" "неизвестно")"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_desc="${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-}}"
    fi
    kernel=$(uname -r 2>/dev/null || echo "$(localized_text "未知" "unknown" "неизвестно")")
    arch=$(uname -m 2>/dev/null || echo "$(localized_text "未知" "unknown" "неизвестно")")
    now=$(date -Is 2>/dev/null || date)
    script_path=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")

    if command -v ufw >/dev/null 2>&1; then
        firewall_status=$(ufw status 2>/dev/null | head -n 5 | tr '\n' '; ')
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall_status=$(firewall-cmd --state 2>/dev/null || echo "$(localized_text "firewalld 未运行" "firewalld is not running" "firewalld не запущен")")
    else
        firewall_status="$(localized_text "未检测到 ufw/firewalld" "ufw/firewalld not detected" "ufw/firewalld не обнаружен")"
    fi

    latest_backups=$(find /etc/vps-optimize/backups -maxdepth 3 -type f -o -type d 2>/dev/null | sort -r | head -n 10)
    [[ -z "$latest_backups" ]] && latest_backups="$(localized_text "未检测到" "not detected" "не обнаружено")"

    log_path=$(find /var/log /tmp /etc/vps-optimize -maxdepth 3 -type f \( -iname '*vps*optimize*.log' -o -iname '*cy*.log' \) 2>/dev/null | sort -r | head -n 5)
    [[ -z "$log_path" ]] && log_path="$(localized_text "未检测到" "not detected" "не обнаружено")"

    echo ""
    echo "$(localized_text "===== VPS-Optimize 反馈诊断信息 =====" "===== VPS-Optimize feedback diagnostic information =====" "===== VPS-Optimize обратная диагностическая информация =====")"
    echo "$(localized_text "系统版本: ${os_desc}" "System version: ${os_desc}" "Версия системы: ${os_desc}")"
    echo "$(localized_text "内核版本: ${kernel}" "Kernel version: ${kernel}" "Версия ядра: ${kernel}.")"
    echo "$(localized_text "CPU 架构: ${arch}" "CPU architecture: ${arch}" "Архитектура процессора: ${arch}")"
    echo "$(localized_text "脚本版本: ${SCRIPT_VERSION}" "Script version: ${SCRIPT_VERSION}" "Версия скрипта: ${SCRIPT_VERSION}")"
    echo "$(localized_text "脚本路径: ${script_path}" "Script path: ${script_path}" "Путь сценария: ${script_path}")"
    echo "$(localized_text "当前时间: ${now}" "Current time: ${now}" "Текущее время: ${now}")"
    echo ""
    print_443_single_entry_issue_summary
    echo ""
    if declare -F print_traffic_guard_diagnostic_summary >/dev/null; then
        print_traffic_guard_diagnostic_summary 5 yes
        echo ""
    fi
    echo "$(localized_text "关键服务状态:" "Critical service status:" "Критический статус услуги:")"
    for svc in nginx caddy docker xray sing-box; do
        echo "- ${svc}: $(service_state_for_issue "$svc")"
    done
    echo "$(localized_text "- 3x-ui 面板: $(xui_panel_state_for_issue)" "- 3x-ui Panel: $(xui_panel_state_for_issue)" "- Панель 3x-ui: $(xui_panel_state_for_issue)")"
    echo ""
    echo "$(localized_text "监听端口摘要:" "Listening port summary:" "Сводка порта прослушивания:")"
    ss -tulnp 2>/dev/null | sed -E 's/users:\(\("[^"]+",pid=[0-9]+,fd=[0-9]+\)\)/users:(process-redacted)/g' | head -n 30 || echo "$(localized_text "未检测到 ss 输出" "ss output not detected" "выход ss не обнаружен")"
    echo ""
    echo "$(localized_text "443 占用情况:" "443 Occupancy:" "443 Вместимость:")"
    ss -tulnp 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || echo "$(localized_text "未检测到 443 监听" "443 listener not detected" "443 прослушиватель не обнаружен")"
    echo ""
    echo "$(localized_text "防火墙状态:" "Firewall status:" "Статус брандмауэра:")"
    echo "${firewall_status}"
    echo ""
    echo "$(localized_text "最近 Nginx 错误日志摘要:" "Summary of recent Nginx error logs:" "Сводка последних журналов ошибок Nginx:")"
    recent_journal_for_issue nginx
    echo ""
    echo "$(localized_text "最近 Caddy 错误日志摘要:" "Summary of recent Caddy error logs:" "Сводка последних журналов ошибок Caddy:")"
    recent_journal_for_issue caddy
    echo ""
    echo "$(localized_text "最近脚本日志路径:" "Recent script log path:" "Путь к журналу последнего сценария:")"
    echo "${log_path}"
    echo ""
    echo "$(localized_text "最近备份列表:" "Recent backup list:" "Список последних резервных копий:")"
    echo "${latest_backups}"
    echo "$(localized_text "===== 诊断信息结束，请提交前再次检查是否有敏感信息 =====" "===== The diagnostic information is over, please check again whether there is sensitive information before submitting =====" "===== Диагностическая информация закончилась, пожалуйста, проверьте еще раз, есть ли конфиденциальная информация перед отправкой =====")"
}
