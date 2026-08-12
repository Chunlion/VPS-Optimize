# shellcheck shell=bash
# Service health dashboard and runtime issue summaries.

print_log_capacity_group() {
    local label="$1"
    local pattern="$2"
    local count=0 total=0 largest_size=0 largest_file="" file size

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        size=$(file_size_bytes "$file")
        count=$((count + 1))
        total=$((total + size))
        if (( size > largest_size )); then
            largest_size="$size"
            largest_file="$file"
        fi
    done < <(compgen -G "$pattern" 2>/dev/null | sort || true)

    if (( count == 0 )); then
        echo "$(localized_text "- ${label}: 未发现日志文件" "- ${label}: Log file not found" "- ${label}: файл журнала не найден.")"
        return 0
    fi

    echo "$(localized_text "- ${label}: ${count} 个文件，总量 $(format_bytes "$total")；最大 $(format_bytes "$largest_size") ${largest_file}" "- ${label}: ${count} files, total $(format_bytes \"$total\"); maximum $(format_bytes \"$largest_size\") ${largest_file}" "- ${label}: файлы ${count}, всего $(format_bytes \"$total\"); максимум $(format_bytes \"$largest_size\") ${largest_file}")"
}

print_log_capacity_summary() {
    echo -e "$(localized_text "${CYAN}🧾 日志容量摘要${PLAIN}" "${CYAN}🧾 Log capacity summary${PLAIN}" "${CYAN}🧾 Сводная информация о емкости журнала${PLAIN}")"
    print_log_capacity_group "/var/log/vps-optimize/*" "/var/log/vps-optimize/*"
    print_log_capacity_group "/var/log/vpso-mux*" "/var/log/vpso-mux*"
    print_log_capacity_group "/var/log/vps-traffic-guard.log" "/var/log/vps-traffic-guard.log*"
    echo "$(localized_text "- Bash 日志默认超过 $(format_bytes "$VPSO_DEFAULT_LOG_MAX_BYTES") 后保留 ${VPSO_DEFAULT_LOG_ROTATE_KEEP} 份轮转副本；systemd journal 仍按系统策略输出。" "- By default, Bash logs retain ${VPSO_DEFAULT_LOG_ROTATE_KEEP} rotating copies after exceeding $(format_bytes \"$VPSO_DEFAULT_LOG_MAX_BYTES\"); systemd journals are still output according to the system policy." "- По умолчанию журналы Bash сохраняют чередующиеся копии ${VPSO_DEFAULT_LOG_ROTATE_KEEP} после превышения $(format_bytes \"$VPSO_DEFAULT_LOG_MAX_BYTES\"); Журналы systemd по-прежнему выводятся в соответствии с системной политикой.")"
    echo "$(localized_text "- 本页只汇总容量；不会轮转或重开已经被长期进程打开的日志 fd。" "- This page only summarizes capacity; log fds that have been opened by long-term processes will not be rotated or reopened." "- На этой странице представлена только информация о мощности; Файлы журналов, открытые длительными процессами, не будут ротироваться или открываться повторно.")"
    echo "$(localized_text "- daemon 直写文件时，请配合 systemd/journal、服务重载/重启，或可重开文件的日志实现。" "- When the daemon directly writes files, please cooperate with systemd/journal, service reload/restart, or log implementation that can reopen the file." "- Когда демон напрямую записывает файлы, сотрудничайте с systemd/journal, перезагрузкой/перезапуском службы или реализацией журнала, которая может повторно открыть файл.")"
}

vpso_permission_mode() {
    local file="$1"
    stat -c '%a' "$file" 2>/dev/null || echo "?"
}

vpso_permission_recommendation() {
    local file="$1"
    local lower
    lower=$(printf '%s' "$file" | tr '[:upper:]' '[:lower:]')

    if [[ -x "$file" && ! -d "$file" ]]; then
        printf "$(localized_text '755|可执行文件' '755|Executable file' '755|Исполняемый файл')"
    elif [[ "$lower" == *.json ]]; then
        printf "$(localized_text '644/640|普通状态 JSON' '644/640|Normal state JSON' '644/640|Нормальное состояние JSON')"
    elif [[ "$lower" =~ (token|secret|private|key|subscription|subscribe|whitelist|sni-stack|xray|caddy|vpso-mux) ]]; then
        printf "$(localized_text '600|可能包含 token、secret、私钥、订阅源或白名单' '600|May contain token, secret, private key, feed or whitelist' '600|Может содержать токен, секретный ключ, закрытый ключ, канал или белый список.')"
    elif [[ "$file" == /etc/vps-optimize/*.conf || "$file" == /etc/vps-optimize/*.yaml ]]; then
        printf "$(localized_text '600|配置文件' '600|Configuration file' '600|Файл конфигурации')"
    elif [[ "$file" == /var/log/* ]]; then
        printf "$(localized_text '640/644|日志文件' '640/644|Log file' '640/644|Файл журнала')"
    else
        printf "$(localized_text '644/640|普通状态文件' '644/640|Normal status file' '644/640|Обычный файл состояния')"
    fi
}

vpso_permission_matches() {
    local mode="$1"
    local expected="$2"
    case "$expected" in
        600) [[ "$mode" == "600" ]] ;;
        755) [[ "$mode" == "755" ]] ;;
        640/644) [[ "$mode" == "640" || "$mode" == "644" ]] ;;
        644/640) [[ "$mode" == "644" || "$mode" == "640" ]] ;;
        *) return 0 ;;
    esac
}

vpso_permission_fix_mode() {
    local expected="$1"
    case "$expected" in
        600|755) printf '%s' "$expected" ;;
        640/644|644/640) printf '640' ;;
        *) printf '' ;;
    esac
}

collect_vpso_permission_files() {
    local pattern
    for pattern in \
        "/etc/vps-optimize/*.conf" \
        "/etc/vps-optimize/*.yaml" \
        "/var/lib/vps-optimize/*" \
        "/var/log/vps-optimize/*"; do
        compgen -G "$pattern" 2>/dev/null || true
    done | sort -u
}

check_vpso_file_permissions() {
    local action="${1:-check}"
    local checked=0 warnings=0 fixed=0 file mode rec expected reason target_mode

    if [[ "$action" == "fix" ]]; then
        confirm_risk_action "$(localized_text "修复 VPS-Optimize 文件权限" "Fix VPS-Optimize file permissions" "Исправьте права доступа к файлу VPS-Optimize.")" \
            "$(localized_text "/etc/vps-optimize、/var/lib/vps-optimize、/var/log/vps-optimize 下权限过宽或不符合建议的文件" "Files under /etc/vps-optimize、/var/lib/vps-optimize、/var/log/vps-optimize whose permissions are too wide or do not meet the recommendations" "Файлы под /etc/vps-optimize、/var/lib/vps-optimize、/var/log/vps-optimize, разрешения которых слишком велики или не соответствуют рекомендациям.")" \
            "$(localized_text "如某个服务因此无法读取文件，可根据本页输出手动 chmod 回原权限，或从备份恢复配置文件" "If a service cannot read the file, you can manually chmod the original permissions according to the output on this page, or restore the configuration file from backup." "Если служба не может прочитать файл, вы можете вручную изменить исходные разрешения в соответствии с выводом на этой странице или восстановить файл конфигурации из резервной копии.")" \
            "$(localized_text "修复前建议确认当前服务状态；本操作不会批量删除文件。" "It is recommended to confirm the current service status before repairing; this operation will not delete files in batches." "Перед ремонтом рекомендуется подтвердить текущий статус обслуживания; эта операция не приведет к пакетному удалению файлов.")" || return 1
    fi

    echo -e "$(localized_text "${CYAN}🔒 配置与状态文件权限体检${PLAIN}" "${CYAN}🔒 Configuration and status file permission check${PLAIN}" "${CYAN}🔒 Проверка разрешений файла конфигурации и состояния${PLAIN}")"
    while IFS= read -r file; do
        [[ -e "$file" && ! -d "$file" ]] || continue
        checked=$((checked + 1))
        mode=$(vpso_permission_mode "$file")
        rec=$(vpso_permission_recommendation "$file")
        expected="${rec%%|*}"
        reason="${rec#*|}"
        if vpso_permission_matches "$mode" "$expected"; then
            echo "$(localized_text "- OK   ${file} mode=${mode} (${reason}; 建议 ${expected})" "- OK ${file} mode=${mode} (${reason}; recommended ${expected})" "- OK режим ${file}=${mode} (${reason}; рекомендуется ${expected})")"
            continue
        fi
        warnings=$((warnings + 1))
        echo "$(localized_text "- WARN ${file} mode=${mode} (${reason}; 建议 ${expected})" "- WARN ${file} mode=${mode} (${reason}; recommended ${expected})" "- Режим WARN ${file}=${mode} (${reason}; рекомендуется ${expected})")"
        if [[ "$action" == "fix" ]]; then
            target_mode=$(vpso_permission_fix_mode "$expected")
            if [[ -n "$target_mode" ]] && chmod "$target_mode" "$file" 2>/dev/null; then
                fixed=$((fixed + 1))
                echo "$(localized_text "       已修复为 ${target_mode}" "Fixed to ${target_mode}" "Исправлено для ${target_mode}.")"
            else
                echo "$(localized_text "       未能自动修复，请手动检查权限。" "Failed to automatically repair, please check permissions manually." "Не удалось выполнить автоматическое восстановление. Проверьте разрешения вручную.")"
            fi
        fi
    done < <(collect_vpso_permission_files)

    if (( checked == 0 )); then
        echo "$(localized_text "- 未发现待检查文件。" "- No files to be checked were found." "- Файлы для проверки не найдены.")"
    else
        echo "$(localized_text "- 已检查 ${checked} 个文件；发现 ${warnings} 个需要关注；本次修复 ${fixed} 个。" "- ${checked} files have been checked; ${warnings} files were found to require attention; ${fixed} files were fixed this time." "- проверены файлы ${checked}; Было обнаружено, что файлы ${warnings} требуют внимания; На этот раз файлы ${fixed} были исправлены.")"
    fi
}

HEALTH_RECOVERY_UNITS=(
    "1|Caddy|caddy.service"
    "2|Nginx|nginx.service"
    "3|Docker|docker.service"
    "4|Fail2ban|fail2ban.service"
    "5|3x-ui|3x-ui.service"
    "6|x-ui|x-ui.service"
    "7|x-panel|x-panel.service"
    "8|Xray|xray.service"
    "9|Sing-box|sing-box.service"
    "10|S-UI|s-ui.service"
    "11|vpso-mux|vpso-mux.service"
    "12|vps-traffic-guard|vps-traffic-guard.service"
)

health_unit_exists() {
    local unit="$1"
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q . && return 0
    systemctl list-units "$unit" --all --no-legend 2>/dev/null | grep -q . && return 0
    systemctl status "$unit" >/dev/null 2>&1
}

health_unit_status_label() {
    local unit="$1"
    if ! health_unit_exists "$unit"; then
        printf '%b' "$(localized_text "${BLUE}未安装${PLAIN}" "${BLUE}Is not installed${PLAIN}" "${BLUE}не установлен${PLAIN}")"
    elif systemctl is-active --quiet "$unit"; then
        printf '%b' "$(localized_text "${GREEN}运行中${PLAIN}" "${GREEN}Running${PLAIN}" "${GREEN}работает${PLAIN}")"
    elif systemctl is-failed --quiet "$unit"; then
        printf '%b' "$(localized_text "${RED}失败${PLAIN}" "${RED}Failed${PLAIN}" "${RED}Ошибка${PLAIN}")"
    else
        printf '%b' "$(localized_text "${YELLOW}未运行${PLAIN}" "${YELLOW}Is not running${PLAIN}" "${YELLOW}не работает${PLAIN}")"
    fi
}

health_system_state_label() {
    local state="${1:-unknown}"
    case "$state" in
        running) printf '%b' "${GREEN}running${PLAIN}" ;;
        degraded) printf '%b' "${YELLOW}degraded${PLAIN}" ;;
        starting|stopping|maintenance|initializing) printf '%b' "${YELLOW}${state}${PLAIN}" ;;
        *) printf '%b' "${RED}${state}${PLAIN}" ;;
    esac
}

print_failed_systemd_units() {
    local count=0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        count=$((count + 1))
        echo "  - ${line}"
    done < <(systemctl --failed --no-legend --no-pager 2>/dev/null | awk 'NF {print $1 " " $2 " " $3 " " $4}' | head -n 12)
    (( count > 0 )) || echo "$(localized_text "  - 未发现失败单元" "- No failed unit found" "- Ни одного неисправного устройства не обнаружено.")"
}

collect_failed_service_units() {
    systemctl --failed --type=service --no-legend --no-pager 2>/dev/null | awk '$1 ~ /\.service$/ {print $1}' | sort -u
}

health_restart_unit() {
    local label="$1"
    local unit="$2"

    if ! health_unit_exists "$unit"; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 ${unit}，跳过。${PLAIN}" "${YELLOW}⚠️ ${unit} not detected, skipped.${PLAIN}" "${YELLOW}⚠️ ${unit} не обнаружен, пропущен.${PLAIN}")"
        return 1
    fi

    systemctl reset-failed "$unit" >/dev/null 2>&1 || true
    if systemctl restart "$unit" >/dev/null 2>&1; then
        echo -e "$(localized_text "${GREEN}✅ ${label} 已重启：${unit}${PLAIN}" "${GREEN}✅ ${label} Restarted: ${unit}${PLAIN}" "${GREEN}✅ ${label} Перезапущен: ${unit}${PLAIN}")"
        return 0
    fi

    echo -e "$(localized_text "${RED}❌ ${label} 重启失败：${unit}${PLAIN}" "${RED}❌ ${label} Restart failed: ${unit}${PLAIN}" "${RED}❌ ${label} Не удалось перезапустить: ${unit}${PLAIN}")"
    journalctl -u "$unit" -n 20 --no-pager 2>/dev/null || true
    return 1
}

health_restart_selected_unit() {
    local item number label unit selected="$1"

    for item in "${HEALTH_RECOVERY_UNITS[@]}"; do
        IFS='|' read -r number label unit <<< "$item"
        if [[ "$selected" == "$number" ]]; then
            confirm_risk_action "$(localized_text "重启 ${label}" "Restart ${label}" "Перезагрузите ${label}.")" \
                "$(localized_text "${unit} 服务进程" "${unit} service process" "${unit} процесс обслуживания")" \
                "$(localized_text "查看 journalctl -u ${unit} 日志，修正配置后重新启动" "Check the journalctl -u ${unit} log, correct the configuration and restart" "Проверьте журнал Journalctl -u ${unit}, исправьте конфигурацию и перезапустите.")" \
                "$(localized_text "该服务会短暂中断；不要关闭当前 SSH 会话。" "The service will be briefly interrupted; do not close the current SSH session." "Обслуживание будет ненадолго прервано; не закрывайте текущую сессию SSH.")" || return 1
            health_restart_unit "$label" "$unit"
            return
        fi
    done

    echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"
    return 1
}

health_restart_failed_services() {
    local failed_units=()
    local unit label ok=0 fail=0 skipped=0

    mapfile -t failed_units < <(collect_failed_service_units)
    if [[ ${#failed_units[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${GREEN}未发现失败服务。${PLAIN}" "${GREEN}No failed service found.${PLAIN}" "${GREEN}Неисправных служб не обнаружено.${PLAIN}")"
        return 0
    fi

    echo -e "$(localized_text "${CYAN}将尝试重启以下失败服务：${PLAIN}" "${CYAN}Will attempt to restart the following failed services:${PLAIN}" "${CYAN}попытается перезапустить следующие отказавшие службы:${PLAIN}")"
    printf '  - %s\n' "${failed_units[@]}"
    confirm_risk_action "$(localized_text "重启失败的 systemd 服务" "Restart failed systemd service" "Не удалось перезапустить службу systemd.")" \
        "$(localized_text "当前处于失败状态的服务单元" "The service unit that is currently in a failed state" "Сервисный блок, который в данный момент находится в неисправном состоянии")" \
        "$(localized_text "查看对应 journalctl 日志，修正配置后单独重启失败服务" "Check the corresponding journalctl log, correct the configuration and restart the failed service individually." "Проверьте соответствующий журнал Journalctl, исправьте конфигурацию и перезапустите отказавшую службу отдельно.")" \
        "$(localized_text "会跳过 ssh/sshd，其他服务会短暂中断。" "ssh/sshd will be skipped and other services will be briefly interrupted." "ssh/sshd будет пропущен, а другие службы будут ненадолго прерваны.")" || return 1

    for unit in "${failed_units[@]}"; do
        case "$unit" in
            ssh.service|sshd.service)
                echo -e "$(localized_text "${YELLOW}⚠️ 跳过 ${unit}，避免影响当前 SSH 会话。${PLAIN}" "${YELLOW}⚠️ Skip ${unit} to avoid affecting the current SSH session.${PLAIN}" "${YELLOW}⚠️ Пропустите ${unit}, чтобы не повлиять на текущий сеанс SSH.${PLAIN}")"
                skipped=$((skipped + 1))
                continue
                ;;
        esac
        label="${unit%.service}"
        if health_restart_unit "$label" "$unit"; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1))
        fi
    done

    systemctl reset-failed >/dev/null 2>&1 || true
    echo -e "$(localized_text "${CYAN}处理结果：成功 ${ok}，失败 ${fail}，跳过 ${skipped}。${PLAIN}" "${CYAN}Processing result: success ${ok}, failure ${fail}, skip ${skipped}.${PLAIN}" "${CYAN}Результат обработки : успех ${ok}, отказ ${fail}, пропуск ${skipped}.${PLAIN}")"
}

health_reset_failed_state() {
    if systemctl reset-failed >/dev/null 2>&1; then
        echo -e "$(localized_text "${GREEN}✅ 已执行 systemctl reset-failed。${PLAIN}" "${GREEN}✅ systemctl reset-failed executed.${PLAIN}" "${GREEN}✅ Не удалось выполнить сброс systemctl.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ reset-failed 执行失败。${PLAIN}" "${RED}❌ reset-failed The execution failed.${PLAIN}" "${RED}❌ не удалось выполнить сброс. Выполнение не удалось.${PLAIN}")"
        return 1
    fi
}

health_enable_auto_restart_for_unit() {
    local item number label unit selected="$1"
    local dropin_dir dropin_file

    for item in "${HEALTH_RECOVERY_UNITS[@]}"; do
        IFS='|' read -r number label unit <<< "$item"
        [[ "$selected" == "$number" ]] || continue

        if [[ "$unit" != *.service ]]; then
            echo -e "$(localized_text "${YELLOW}⚠️ ${unit} 不是服务单元，跳过自动重启配置。${PLAIN}" "${YELLOW}⚠️ ${unit} is not a service unit and skips automatic restart configuration.${PLAIN}" "${YELLOW}⚠️ ${unit} не является сервисным устройством и пропускает настройку автоматического перезапуска.${PLAIN}")"
            return 1
        fi
        if ! health_unit_exists "$unit"; then
            echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 ${unit}，跳过。${PLAIN}" "${YELLOW}⚠️ ${unit} not detected, skipped.${PLAIN}" "${YELLOW}⚠️ ${unit} не обнаружен, пропущен.${PLAIN}")"
            return 1
        fi

        confirm_risk_action "$(localized_text "启用 ${label} 失败自动重启" "Enable automatic restart on ${label} failure" "Включить автоматический перезапуск при сбое ${label}.")" \
            "/etc/systemd/system/${unit}.d/10-vps-optimize-restart.conf" \
            "$(localized_text "删除该 drop-in 后执行 systemctl daemon-reload" "After deleting the drop-in, execute systemctl daemon-reload" "После удаления вставки выполните systemctl daemon-reload")" \
            "$(localized_text "服务崩溃后 systemd 会自动拉起；配置错误仍需要查看日志修复。" "After the service crashes, systemd will be automatically pulled up; configuration errors still need to be checked and fixed in the log." "После сбоя службы systemd будет автоматически загружен; ошибки конфигурации все равно нужно проверять и фиксировать в журнале.")" || return 1

        dropin_dir="/etc/systemd/system/${unit}.d"
        dropin_file="${dropin_dir}/10-vps-optimize-restart.conf"
        mkdir -p "$dropin_dir" || { echo -e "$(localized_text "${RED}❌ 创建 drop-in 目录失败。${PLAIN}" "${RED}❌ Failed to create drop-in directory.${PLAIN}" "${RED}❌ Не удалось создать каталог для вставки.${PLAIN}")"; return 1; }
        cat > "$dropin_file" <<'EOF'
[Service]
Restart=on-failure
RestartSec=5s
EOF
        systemctl daemon-reload >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ systemctl daemon-reload 失败。${PLAIN}" "${RED}❌ systemctl daemon-reload failed.${PLAIN}" "${RED}❌ Ошибка перезагрузки демона systemctl.${PLAIN}")"; return 1; }
        systemctl enable "$unit" >/dev/null 2>&1 || true
        echo -e "$(localized_text "${GREEN}✅ 已启用自动重启：${dropin_file}${PLAIN}" "${GREEN}✅ Auto-restart enabled: ${dropin_file}${PLAIN}" "${GREEN}✅ Автоматический перезапуск включен: ${dropin_file}${PLAIN}")"
        health_restart_unit "$label" "$unit" || true
        return
    done

    echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"
    return 1
}

health_show_failed_unit_logs() {
    local unit choice i
    local failed_units=()

    mapfile -t failed_units < <(collect_failed_service_units)
    if [[ ${#failed_units[@]} -gt 0 ]]; then
        echo -e "$(localized_text "${CYAN}失败服务：${PLAIN}" "${CYAN}Failed service:${PLAIN}" "${CYAN}не удалось выполнить обслуживание:${PLAIN}")"
        for i in "${!failed_units[@]}"; do
            echo -e "${GREEN} $((i + 1)). ${failed_units[$i]}${PLAIN}"
        done
        echo "$(localized_text " 0. 输入其他服务名" "0. Enter another service name" "0. Введите другое имя службы.")"
        read_trimmed choice "$(localized_text "输入编号或服务名: " "Enter a number or service name: " "Введите номер или имя службы: ")"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#failed_units[@]} )); then
            unit="${failed_units[$((choice - 1))]}"
        elif [[ "$choice" == "0" ]]; then
            read_trimmed unit "$(localized_text "请输入服务名（例如 caddy.service）: " "Please enter the service name (for example caddy.service):" "Введите имя службы (например, caddy.service):")"
        elif [[ "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "$(localized_text "${RED}❌ 编号无效。${PLAIN}" "${RED}❌ The number is invalid.${PLAIN}" "${RED}❌ Номер недействителен.${PLAIN}")"
            return 1
        else
            unit="$choice"
        fi
    else
        read_trimmed unit "$(localized_text "请输入服务名（例如 caddy.service）: " "Please enter the service name (for example caddy.service):" "Введите имя службы (например, caddy.service):")"
    fi
    [[ -n "$unit" ]] || return 0
    [[ "$unit" == *.service || "$unit" == *.timer || "$unit" == *.socket ]] || unit="${unit}.service"
    if ! health_unit_exists "$unit"; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 ${unit}。${PLAIN}" "${YELLOW}⚠️ ${unit} not detected.${PLAIN}" "${YELLOW}⚠️ ${unit} не обнаружен.${PLAIN}")"
        return 1
    fi
    journalctl -u "$unit" -n 80 --no-pager 2>/dev/null || true
}

func_health_service_recovery_menu() {
    local choice

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "诊断/健康检查 > 服务恢复" "Diagnostics/Health Checks > Service recovery" "Диагностика/Проверка состояния > Восстановление служб")"
        echo -e "$(localized_text "${BOLD}🧰 服务恢复与自动重启${PLAIN}" "${BOLD}🧰 Service recovery and automatic restart${PLAIN}" "${BOLD}🧰 Восстановление и автоматический перезапуск служб${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${CYAN}失败的 systemd 单元：${PLAIN}" "${CYAN}Failed systemd units:${PLAIN}" "${CYAN}Сбойные юниты systemd:${PLAIN}")"
        print_failed_systemd_units
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}常用服务${PLAIN}" "${BOLD}Common services${PLAIN}" "${BOLD}Основные службы${PLAIN}")"
        local item number label unit
        for item in "${HEALTH_RECOVERY_UNITS[@]}"; do
            IFS='|' read -r number label unit <<< "$item"
            echo -e "${GREEN} ${number}. ${label}${PLAIN} [${unit}] $(health_unit_status_label "$unit")"
        done
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN} r. 重启常用服务${PLAIN}" "${GREEN} r. Restart a common service${PLAIN}" "${GREEN} r. Перезапустить основную службу${PLAIN}")"
        echo -e "$(localized_text "${GREEN} f. 重启失败服务${PLAIN}" "${GREEN} f. Restart failed services${PLAIN}" "${GREEN} f. Перезапустить сбойные службы${PLAIN}")"
        echo -e "$(localized_text "${GREEN} a. 启用失败自动重启${PLAIN}" "${GREEN} a. Enable restart on failure${PLAIN}" "${GREEN} a. Включить перезапуск при сбое${PLAIN}")"
        echo -e "$(localized_text "${GREEN} x. 清除已恢复的失败状态${PLAIN}" "${GREEN} x. Clear recovered failure states${PLAIN}" "${GREEN} x. Очистить восстановленные состояния сбоя${PLAIN}")"
        echo -e "$(localized_text "${GREEN} l. 查看服务日志${PLAIN}" "${GREEN} l. View service logs${PLAIN}" "${GREEN} l. Показать журналы служб${PLAIN}")"
        echo -e "$(localized_text "${RED} 0. 返回上级菜单 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        read_trimmed choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
        case "$choice" in
            r|R)
                read_trimmed choice "$(localized_text "请输入要重启的服务编号: " "Please enter the service number to be restarted:" "Пожалуйста, введите номер услуги для перезапуска:")"
                health_restart_selected_unit "$choice"
                pause_return
                ;;
            f|F)
                health_restart_failed_services
                pause_return
                ;;
            a|A)
                read_trimmed choice "$(localized_text "请输入要启用自动重启的服务编号: " "Please enter the service ID for which you want to enable automatic restart:" "Введите идентификатор службы, для которой вы хотите включить автоматический перезапуск:")"
                health_enable_auto_restart_for_unit "$choice"
                pause_return
                ;;
            x|X)
                health_reset_failed_state
                pause_return
                ;;
            l|L)
                health_show_failed_unit_logs
                pause_return
                ;;
            0|q|Q) return ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"; sleep 1 ;;
        esac
    done
}

func_health_dashboard() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "$(localized_text "诊断 / 健康检查" "Diagnostics / Health checks" "Диагностика / Проверка состояния")"
    echo -e "$(localized_text "${BOLD}📈 服务健康总览${PLAIN}" "${BOLD}📈 Service health overview${PLAIN}" "${BOLD}📈 Состояние служб${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local ssh_state="$(localized_text "${RED}未运行${PLAIN}" "${RED}Is not running${PLAIN}" "${RED}не работает${PLAIN}")"
    if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
        ssh_state="$(localized_text "${GREEN}运行中${PLAIN}" "${GREEN}Running${PLAIN}" "${GREEN}работает${PLAIN}")"
    fi

    local caddy_state="$(localized_text "${RED}未安装/未运行${PLAIN}" "${RED}Is not installed/not running${PLAIN}" "${RED}не установлен/не запущен${PLAIN}")"
    if command -v caddy >/dev/null 2>&1; then
        if systemctl is-active --quiet caddy; then
            caddy_state="$(localized_text "${GREEN}运行中${PLAIN}" "${GREEN}Running${PLAIN}" "${GREEN}работает${PLAIN}")"
        else
            caddy_state="$(localized_text "${YELLOW}已安装但未运行${PLAIN}" "${YELLOW}Is installed but not running${PLAIN}" "${YELLOW}установлен, но не работает${PLAIN}")"
        fi
    fi

    local docker_state="$(localized_text "${RED}未安装/未运行${PLAIN}" "${RED}Is not installed/not running${PLAIN}" "${RED}не установлен/не запущен${PLAIN}")"
    if command -v docker >/dev/null 2>&1; then
        if systemctl is-active --quiet docker; then
            docker_state="$(localized_text "${GREEN}运行中${PLAIN}" "${GREEN}Running${PLAIN}" "${GREEN}работает${PLAIN}")"
        else
            docker_state="$(localized_text "${YELLOW}已安装但未运行${PLAIN}" "${YELLOW}Is installed but not running${PLAIN}" "${YELLOW}установлен, но не работает${PLAIN}")"
        fi
    fi

    local f2b_state="$(localized_text "${RED}未安装${PLAIN}" "${RED}Is not installed${PLAIN}" "${RED}не установлен${PLAIN}")"
    if command -v fail2ban-server >/dev/null 2>&1; then
        if systemctl is-active --quiet fail2ban; then
            f2b_state="$(localized_text "${GREEN}运行中${PLAIN}" "${GREEN}Running${PLAIN}" "${GREEN}работает${PLAIN}")"
        else
            f2b_state="$(localized_text "${YELLOW}已安装但未运行${PLAIN}" "${YELLOW}Is installed but not running${PLAIN}" "${YELLOW}установлен, но не работает${PLAIN}")"
        fi
    fi

    local fw_state="$(localized_text "${RED}未启用${PLAIN}" "${RED}Is not enabled${PLAIN}" "${RED}не включен${PLAIN}")"
    if is_debian; then
        if ufw status 2>/dev/null | grep -qwi active; then
            fw_state="$(localized_text "${GREEN}UFW 运行中${PLAIN}" "${GREEN}UFW Running${PLAIN}" "${GREEN}UFW Работает${PLAIN}")"
        else
            fw_state="$(localized_text "${YELLOW}UFW 未启用${PLAIN}" "${YELLOW}UFW  is not enabled${PLAIN}" "${YELLOW}UFW  не включен${PLAIN}")"
        fi
    else
        if systemctl is-active --quiet firewalld; then
            fw_state="$(localized_text "${GREEN}Firewalld 运行中${PLAIN}" "${GREEN}Firewalld is running${PLAIN}" "${GREEN}Firewalld работает под управлением${PLAIN}")"
        else
            fw_state="$(localized_text "${YELLOW}Firewalld 未启用${PLAIN}" "${YELLOW}Firewalld is not enabled${PLAIN}" "${YELLOW}Firewalld не включен${PLAIN}")"
        fi
    fi

    local current_p
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    [[ -z "$current_p" ]] && current_p=$(grep -i '^Port' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    current_p=${current_p:-22}

    local failed_units
    failed_units=$(systemctl --failed --no-legend 2>/dev/null | grep -c .)
    local system_state
    system_state=$(systemctl is-system-running 2>/dev/null || true)
    [[ -z "$system_state" ]] && system_state="unknown"

    echo -e "$(localized_text "SSH 服务状态       : [ $ssh_state ]  监听端口: ${CYAN}${current_p}${PLAIN}" "SSH Service status: [ $ssh_state ] Listening port: ${CYAN}${current_p}${PLAIN}" "SSH Статус службы: [ $ssh_state ] Порт прослушивания: ${CYAN}${current_p}${PLAIN}")"
    echo -e "$(localized_text "Caddy 服务状态     : [ $caddy_state ]" "Caddy Service status: [ $caddy_state ]" "Caddy Статус обслуживания: [ $caddy_state ]")"
    echo -e "$(localized_text "Docker 服务状态    : [ $docker_state ]" "Docker Service status: [ $docker_state ]" "Docker Статус обслуживания: [ $docker_state ]")"
    echo -e "$(localized_text "Fail2ban 服务状态  : [ $f2b_state ]" "Fail2ban Service status: [ $f2b_state ]" "Fail2ban Статус обслуживания: [ $f2b_state ]")"
    echo -e "$(localized_text "防火墙服务状态      : [ $fw_state ]" "Firewall service status: [$fw_state]" "Статус службы брандмауэра: [$fw_state]")"
    echo -e "$(localized_text "systemd 整体状态    : [ $(health_system_state_label "$system_state") ]" "systemd Overall status: [ $(health_system_state_label \"$system_state\") ]" "systemd Общий статус: [ $(health_system_state_label \"$system_state\") ]")"
    echo -e "$(localized_text "失败 systemd 单元数 : ${YELLOW}${failed_units}${PLAIN}" "Failure systemd Number of units: ${YELLOW}${failed_units}${PLAIN}" "Сбой systemd Количество единиц: ${YELLOW}${failed_units}${PLAIN}")"
    echo -e "------------------------------------------------"
    print_project_runtime_overview
    echo -e "------------------------------------------------"
    print_log_capacity_summary
    echo -e "------------------------------------------------"
    if declare -F print_port_connlimit_health_summary >/dev/null; then
        print_port_connlimit_health_summary
        echo -e "------------------------------------------------"
    fi

    echo -e "$(localized_text "${CYAN}🔌 当前监听端口 Top 12${PLAIN}" "${CYAN}🔌 Current listening port Top 12${PLAIN}" "${CYAN}🔌 Текущий порт прослушивания Топ 12${PLAIN}")"
    ss -tuln 2>/dev/null | grep -E 'LISTEN|UNCONN' | awk '{print $5}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' | sort -nu | head -n 12 | tr '\n' ' '
    echo ""

    local cert_root="/var/lib/caddy/.local/share/caddy/certificates"
    [[ ! -d "$cert_root" ]] && cert_root="/root/.local/share/caddy/certificates"

    if [[ -d "$cert_root" ]]; then
        local cert_total=0
        local cert_warn=0
        while IFS= read -r crt; do
            local end_date ts_left days_left
            end_date=$(openssl x509 -enddate -noout -in "$crt" 2>/dev/null | cut -d= -f2-)
            if [[ -n "$end_date" ]]; then
                ts_left=$(( $(date -d "$end_date" +%s 2>/dev/null) - $(date +%s) ))
                days_left=$(( ts_left / 86400 ))
                cert_total=$((cert_total+1))
                if [[ "$days_left" -le 15 ]]; then
                    cert_warn=$((cert_warn+1))
                fi
            fi
        done < <(find "$cert_root" -type f -name "*.crt" 2>/dev/null)

        echo -e "$(localized_text "${CYAN}🔐 证书健康摘要${PLAIN}" "${CYAN}🔐 Certificate Health Summary${PLAIN}" "${CYAN}🔐 Сводная информация о состоянии сертификата${PLAIN}")"
        if [[ "$cert_total" -eq 0 ]]; then
            echo -e "$(localized_text "${BLUE}ℹ️ 未检索到可分析证书文件。${PLAIN}" "${BLUE}ℹ️ No analyzable certificate file retrieved.${PLAIN}" "${BLUE}ℹ️ Не получен файл сертификата, пригодный для анализа.${PLAIN}")"
        else
            echo -e "$(localized_text "证书总数: ${GREEN}${cert_total}${PLAIN} | 15天内到期: ${YELLOW}${cert_warn}${PLAIN}" "Total number of certificates: ${GREEN}${cert_total}${PLAIN} | Expiration within 15 days: ${YELLOW}${cert_warn}${PLAIN}" "Общее количество сертификатов: ${GREEN}${cert_total}${PLAIN} | Срок действия в течение 15 дней: ${YELLOW}${cert_warn}${PLAIN}.")"
        fi
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${YELLOW}💡 若失败单元 > 0，可进入 s 服务恢复处理。${PLAIN}" "${YELLOW}💡 If the failed unit > 0, you can enter s service recovery processing.${PLAIN}" "${YELLOW}💡 Если неисправный блок > 0, вы можете запустить процедуру восстановления службы.${PLAIN}")"
    echo -e "$(localized_text "${CYAN}输入 s 服务恢复，输入 d 生成反馈诊断信息，输入 p 查看权限体检，输入 P 修复权限，输入 ? 查看帮助，其他任意键返回。${PLAIN}" "${CYAN}Enter s for service recovery, enter d to generate feedback diagnostic information, enter p to view permission health check, enter P to repair permission, enter ? to view help, and any other key to return.${PLAIN}" "${CYAN}Введите s, чтобы восстановить службу, введите d, чтобы получить диагностическую информацию обратной связи, введите p, чтобы просмотреть проверку работоспособности разрешений, введите P, чтобы восстановить разрешения, введите ? для просмотра справки и любой другой клавиши для возврата.${PLAIN}")"
    local health_choice
    read -n 1 -s -r health_choice
    echo ""
    case "$health_choice" in
        s|S) func_health_service_recovery_menu ;;
        d|D) generate_issue_diagnostics; pause_return ;;
        p) check_vpso_file_permissions; pause_return ;;
        P) check_vpso_file_permissions fix; pause_return ;;
        "?") show_health_help; pause_return ;;
    esac
}
