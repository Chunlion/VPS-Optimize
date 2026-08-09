# shellcheck shell=bash
# 443 entry mode state, listener detection, and compatibility helpers.

sni_stack_env_path() {
    echo "/etc/vps-optimize/sni-stack.env"
}

canonical_legacy_entry_mode_name() {
    case "$1" in
        "nginx_stream") echo "nginx-stream" ;;
        "xray_fallback") echo "xray-fallback" ;;
        "tcp_peek") echo "tcp-peek" ;;
        *) return 1 ;;
    esac
}

rewrite_legacy_entry_mode_assignment() {
    local file="$1"
    local key="$2"
    local legacy_value="$3"
    local canonical_value assignment_count

    canonical_value=$(canonical_legacy_entry_mode_name "$legacy_value" 2>/dev/null) || return 1
    [[ -f "$file" && -w "$file" ]] || return 1

    assignment_count=$(grep -Ec "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null || true)
    [[ "$assignment_count" == "1" ]] || return 1
    grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*('${legacy_value}'|\"${legacy_value}\"|${legacy_value})[[:space:]]*$" "$file" 2>/dev/null || return 1

    sed -i -E \
        -e "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)'${legacy_value}'[[:space:]]*$|\\1'${canonical_value}'|" \
        -e "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)\"${legacy_value}\"[[:space:]]*$|\\1\"${canonical_value}\"|" \
        -e "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)${legacy_value}[[:space:]]*$|\\1${canonical_value}|" \
        "$file"
}

get_entry_mode() {
    local env_file mode=""
    env_file=$(sni_stack_env_path)

    if [[ ! -f "$env_file" ]]; then
        echo "not-configured"
        return 0
    fi

    mode=$(
        # shellcheck disable=SC1090
        unset ENTRY_MODE
        source "$env_file" 2>/dev/null || true
        printf '%s' "${ENTRY_MODE:-}"
    )

    case "$mode" in
        ""|"nginx-stream"|"nginx_stream")
            rewrite_legacy_entry_mode_assignment "$env_file" "ENTRY_MODE" "$mode" 2>/dev/null || true
            echo "nginx-stream"
            ;;
        "xray-fallback"|"xray_fallback")
            rewrite_legacy_entry_mode_assignment "$env_file" "ENTRY_MODE" "$mode" 2>/dev/null || true
            echo "xray-fallback"
            ;;
        "tcp-peek"|"tcp_peek")
            rewrite_legacy_entry_mode_assignment "$env_file" "ENTRY_MODE" "$mode" 2>/dev/null || true
            echo "tcp-peek"
            ;;
        *)
            echo "invalid:${mode}"
            ;;
    esac
}

print_entry_mode_compat_notice() {
    local env_file
    local state_file env_mode state_engine normalized
    env_file=$(sni_stack_env_path)
    state_file=$(single_443_engine_state_path 2>/dev/null || echo "/etc/vps-optimize/443-engine.conf")

    if [[ -f "$env_file" ]]; then
        env_mode=$(
            # shellcheck disable=SC1090
            unset ENTRY_MODE
            source "$env_file" 2>/dev/null || true
            printf '%s' "${ENTRY_MODE:-}"
        )
        if [[ -z "$env_mode" ]]; then
            echo -e "$(localized_text "${YELLOW}兼容提示：${env_file} 未写 ENTRY_MODE，已按 nginx-stream 读取；下次保存会写入 ENTRY_MODE='nginx-stream'。${PLAIN}" "${YELLOW}Compatibility tip: ${env_file} has not written ENTRY_MODE and has been read according to nginx-stream; next time it is saved, ENTRY_MODE='nginx-stream' will be written.${PLAIN}" "${YELLOW}Примечание о совместимости: ${env_file} не записал ENTRY_MODE и был прочитан в соответствии с потоком nginx; при следующем сохранении будет записано ENTRY_MODE='nginx-stream'.${PLAIN}")"
        else
            case "$env_mode" in
                "nginx_stream"|"xray_fallback"|"tcp_peek")
                    normalized=$(normalize_entry_mode_name "$env_mode" 2>/dev/null || echo "nginx-stream")
                    if ! rewrite_legacy_entry_mode_assignment "$env_file" "ENTRY_MODE" "$env_mode" 2>/dev/null; then
                        echo -e "$(localized_text "${YELLOW}兼容提示：检测到旧 ENTRY_MODE='${env_mode}'，当前按 '${normalized}' 读取；下次保存会写入新命名。${PLAIN}" "${YELLOW}Compatibility tip: The old ENTRY_MODE='${env_mode}' is detected, currently read by '${normalized}'; the new name will be written next time you save.${PLAIN}" "${YELLOW}Примечание о совместимости: обнаружен старый ENTRY_MODE='${env_mode}', который в настоящее время читается '${normalized}'; новое имя будет записано при следующем сохранении.${PLAIN}")"
                    fi
                    ;;
            esac
        fi
    fi

    if [[ -f "$state_file" ]]; then
        state_engine=$(
            # shellcheck disable=SC1090
            unset engine
            source "$state_file" 2>/dev/null || true
            printf '%s' "${engine:-}"
        )
        case "$state_engine" in
            "nginx_stream"|"xray_fallback"|"tcp_peek")
                normalized=$(normalize_entry_mode_name "$state_engine" 2>/dev/null || echo "nginx-stream")
                if ! rewrite_legacy_entry_mode_assignment "$state_file" "engine" "$state_engine" 2>/dev/null; then
                    echo -e "$(localized_text "${YELLOW}兼容提示：检测到旧 engine='${state_engine}'，当前按 '${normalized}' 读取；下次切换/重新应用会写入新命名。${PLAIN}" "${YELLOW}compatibility tip: The old engine='${state_engine}' is detected, currently read by '${normalized}'; the new name will be written next time you switch/reapply.${PLAIN}" "Совет по совместимости с ${YELLOW}: обнаружен старый engine=\"${state_engine}\", который в настоящее время читается \"${normalized}\"; новое имя будет записано при следующем переключении/повторной подаче заявки.${PLAIN}")"
                fi
                ;;
        esac
    fi
}

set_entry_mode() {
    local mode="$1"
    local env_file
    env_file=$(sni_stack_env_path)

    case "$mode" in
        "nginx_stream") mode="nginx-stream" ;;
        "xray_fallback") mode="xray-fallback" ;;
        "tcp_peek") mode="tcp-peek" ;;
    esac

    case "$mode" in
        "nginx-stream"|"xray-fallback"|"tcp-peek") ;;
        *)
            echo -e "${RED}Invalid ENTRY_MODE: ${mode}${PLAIN}"
            return 1
            ;;
    esac

    mkdir -p "$(dirname "$env_file")"
    if [[ -f "$env_file" ]] && grep -q '^ENTRY_MODE=' "$env_file" 2>/dev/null; then
        sed -i "s|^ENTRY_MODE=.*|ENTRY_MODE='${mode}'|" "$env_file"
    else
        printf "ENTRY_MODE='%s'\n" "$mode" >> "$env_file"
    fi
    chmod 600 "$env_file" 2>/dev/null || true
}

listen_process_from_ss_line() {
    local line="$1"
    local proc
    proc=$(printf '%s\n' "$line" | awk -F'"' '/users:/ {print $2; exit}')
    printf '%s' "${proc:-unknown}"
}

normalize_entry_listener_process() {
    local proc="$1"
    case "$proc" in
        nginx*) echo "nginx" ;;
        xray*|x-ui*|3x-ui*) echo "xray" ;;
        vpso-mux*|tcppeek*|tcp-peek*) echo "tcppeek" ;;
        caddy*) echo "caddy" ;;
        unknown|"") echo "unknown" ;;
        *) echo "unknown:${proc}" ;;
    esac
}

entry_listener_display_name() {
    local listener="$1"
    case "$listener" in
        nginx) echo "Nginx Stream (nginx)" ;;
        xray) echo "Xray Fallback (xray/3x-ui/x-ui)" ;;
        tcppeek) echo "$(localized_text "TCP Peek + Splice 模式 (vpso-mux 分流器)" "TCP Peek + Splice mode (vpso-mux routing)" "Режим TCP Peek + Splice (маршрутизация vpso-mux)")" ;;
        caddy) echo "$(localized_text "Caddy（不应直接接管 443端口复用）" "Caddy (should not take over the Port 443 Reuse directly)" "Caddy (не должен напрямую контролировать повторное использование порта 443)")" ;;
        none) echo "$(localized_text "未监听" "Not listening" "Не слушаю")" ;;
        multiple) echo "$(localized_text "多个进程监听/匹配" "Multiple process listening/matching" "Прослушивание/сопоставление нескольких процессов")" ;;
        unknown) echo "$(localized_text "已监听，但进程不可见" "Listened but the process is not visible" "Слушал но процесса не видно")" ;;
        unknown:*) echo "$(localized_text "未知进程 ${listener#unknown:}" "Unknown process ${listener#unknown:}" "Неизвестный процесс ${listener#unknown:}")" ;;
        *) echo "$listener" ;;
    esac
}

entry_mode_expected_listener() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode" 2>/dev/null || echo "$mode")
    case "$mode" in
        "nginx-stream") echo "nginx" ;;
        "xray-fallback") echo "xray" ;;
        "tcp-peek") echo "tcppeek" ;;
        *) echo "" ;;
    esac
}

listen_line_status() {
    local addr="$1"
    local port="$2"
    local line="$3"
    local proc

    if [[ "$addr" == "not-configured" || "$port" == "not-configured" ]]; then
        echo "$(localized_text "未配置" "Not configured" "Не настроено")"
        return 0
    fi
    if [[ -z "$line" || "$line" == "未监听" || "$line" == "not-configured" ]]; then
        echo "$(localized_text "未监听" "Not listening" "Не слушаю")"
        return 0
    fi

    proc=$(listen_process_from_ss_line "$line")
    if [[ "$proc" == "unknown" ]]; then
        echo "$(localized_text "已监听（进程不可见）" "Listened (process not visible)" "Прослушивается (процесс не виден)")"
    else
        echo "$(localized_text "已监听（${proc}）" "Monitored (${proc})" "Контролируемый (${proc})")"
    fi
}

detect_443_listener() {
    local port="${1:-${NGINX_LISTEN_PORT:-443}}"
    local lines line proc normalized seen procs
    lines=$(ss -lntp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print}' || true)

    if [[ -z "$lines" ]]; then
        echo "none|none"
        return 0
    fi

    seen=" "
    procs=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        proc=$(listen_process_from_ss_line "$line")
        normalized=$(normalize_entry_listener_process "$proc")
        if [[ "$seen" != *" ${normalized} "* ]]; then
            seen+="${normalized} "
            if [[ -z "$procs" ]]; then
                procs="$normalized"
            else
                procs="${procs},${normalized}"
            fi
        fi
    done <<< "$lines"

    if [[ "$procs" == *,* ]]; then
        echo "multiple|${procs}"
    else
        echo "${procs}|${procs}"
    fi
}

listener_info_has_entry() {
    local listener_info="$1"
    local expected="$2"
    local primary labels
    primary="${listener_info%%|*}"
    labels="${listener_info#*|}"
    [[ "$primary" == "$expected" || ",${labels}," == *",${expected},"* ]]
}

detect_current_entry_status() {
    local env_file
    local listener_info expected_listener xui_svc xui_status
    env_file=$(sni_stack_env_path)

    ENTRY_STATUS_MODE=$(get_entry_mode)
    ENTRY_STATUS_CADDY_ADDR="not-configured"
    ENTRY_STATUS_CADDY_PORT="not-configured"
    ENTRY_STATUS_XRAY_ADDR="not-configured"
    ENTRY_STATUS_XRAY_PORT="not-configured"

    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file" 2>/dev/null || true
        ENTRY_STATUS_CADDY_ADDR="${CADDY_LISTEN_ADDR:-not-configured}"
        ENTRY_STATUS_CADDY_PORT="${CADDY_LISTEN_PORT:-not-configured}"
        ENTRY_STATUS_XRAY_ADDR="${XRAY_LISTEN_ADDR:-not-configured}"
        ENTRY_STATUS_XRAY_PORT="${XRAY_LISTEN_PORT:-not-configured}"
    fi

    listener_info=$(detect_443_listener)
    ENTRY_STATUS_LISTENER="${listener_info%%|*}"
    ENTRY_STATUS_LISTENER_PROCESS="${listener_info#*|}"
    ENTRY_STATUS_LISTENER_DISPLAY=$(entry_listener_display_name "$ENTRY_STATUS_LISTENER")
    ENTRY_STATUS_NGINX_SERVICE=$(service_status_compact nginx)
    xui_status=$(xui_panel_status_compact)
    if xui_svc=$(xui_panel_service_name 2>/dev/null); then
        xui_status="${xui_svc}.service ${xui_status}"
    fi
    ENTRY_STATUS_XRAY_SERVICE="$(localized_text "面板托管 Xray: ${xui_status} / 独立 xray.service: $(service_status_compact xray)" "Panel hosting Xray: ${xui_status} / Standalone xray.service: $(service_status_compact xray)" "Хостинг панели Xray: ${xui_status} / Автономный xray.service: $(service_status_compact xray)")"
    ENTRY_STATUS_TCPPEEK_SERVICE=$(service_status_compact vpso-mux)
    ENTRY_STATUS_CADDY_LISTEN_LINE="not-configured"
    ENTRY_STATUS_XRAY_LISTEN_LINE="not-configured"

    if is_valid_port "$ENTRY_STATUS_CADDY_PORT"; then
        ENTRY_STATUS_CADDY_LISTEN_LINE=$(get_listen_line_by_port "$ENTRY_STATUS_CADDY_PORT")
    fi
    if is_valid_port "$ENTRY_STATUS_XRAY_PORT"; then
        ENTRY_STATUS_XRAY_LISTEN_LINE=$(get_listen_line_by_port "$ENTRY_STATUS_XRAY_PORT")
    fi

    expected_listener=$(entry_mode_expected_listener "$ENTRY_STATUS_MODE")

    if [[ -n "$expected_listener" ]] && listener_info_has_entry "$listener_info" "$expected_listener"; then
        ENTRY_STATUS_CONSISTENT="yes"
    else
        ENTRY_STATUS_CONSISTENT="no"
    fi
}

show_current_entry_status() {
    detect_current_entry_status
    echo -e "$(localized_text "${BOLD}当前 443 入口状态${PLAIN}" "${BOLD}Current 443 entry status${PLAIN}" "${BOLD}текущий статус записи 443${PLAIN}")"
    echo -e "$(localized_text "配置模式：${CYAN}${ENTRY_STATUS_MODE}${PLAIN}" "Configuration mode: ${CYAN}${ENTRY_STATUS_MODE}${PLAIN}" "Режим конфигурации: ${CYAN}${ENTRY_STATUS_MODE}${PLAIN}")"
    print_entry_mode_compat_notice
    echo -e "$(localized_text "公网 443：${ENTRY_STATUS_LISTENER_DISPLAY}" "public port 443: ${ENTRY_STATUS_LISTENER_DISPLAY}" "публичный порт 443: ${ENTRY_STATUS_LISTENER_DISPLAY}")"
    echo -e "$(localized_text "监听进程：${ENTRY_STATUS_LISTENER_PROCESS}" "Listening process: ${ENTRY_STATUS_LISTENER_PROCESS}" "Процесс прослушивания: ${ENTRY_STATUS_LISTENER_PROCESS}")"
    if [[ "$ENTRY_STATUS_LISTENER" == "xray" ]]; then
        echo -e "$(localized_text "Xray 公网：${GREEN}公网 443 当前由 Xray/面板托管 Xray 监听${PLAIN}" "Xray Internet: ${GREEN} public port 443 currently hosted by Xray/panel Xray listening on ${PLAIN}" "Xray Публичная сеть: ${GREEN}публичный порт 443 в настоящее время размещается на Xray/панель Xray контролирует${PLAIN}")"
    else
        echo -e "$(localized_text "Xray 公网：未检测到 Xray 监听公网 443" "Xray public: Not detected Xray listening public port 443" "Xray Публичная сеть: не обнаружена Xray прослушивание публичного порта 443")"
    fi
    if [[ "$ENTRY_STATUS_CONSISTENT" == "yes" ]]; then
        echo -e "$(localized_text "一致性：${GREEN}配置模式与实际监听一致${PLAIN}" "Consistency: ${GREEN}Configuration mode is consistent with actual listening${PLAIN}" "Согласованность: режим конфигурации ${GREEN}соответствует реальному прослушиваниеу${PLAIN}.")"
    else
        echo -e "$(localized_text "一致性：${YELLOW}配置模式与实际监听不一致${PLAIN}" "Consistency: ${YELLOW}Configuration mode is inconsistent with actual listening${PLAIN}" "Согласованность: режим конфигурации ${YELLOW}не соответствует фактическому прослушиваниеу${PLAIN}.")"
        echo -e "$(localized_text "${YELLOW}配置模式与实际监听不一致，建议重新应用当前入口模式。${PLAIN}" "${YELLOW}Configuration mode is inconsistent with actual listening. It is recommended to re-apply the current entry mode.${PLAIN}" "${YELLOW}Режим конфигурации несовместим с реальным прослушиваниеом. Рекомендуется повторно применить текущий режим входа.${PLAIN}")"
    fi
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}本地监听${PLAIN}" "${BOLD}Local listeners${PLAIN}" "${BOLD}локальный прослушивание${PLAIN}")"
    echo -e "Caddy：${ENTRY_STATUS_CADDY_ADDR}:${ENTRY_STATUS_CADDY_PORT} - $(listen_line_status "$ENTRY_STATUS_CADDY_ADDR" "$ENTRY_STATUS_CADDY_PORT" "$ENTRY_STATUS_CADDY_LISTEN_LINE")"
    echo -e "Xray： ${ENTRY_STATUS_XRAY_ADDR}:${ENTRY_STATUS_XRAY_PORT} - $(listen_line_status "$ENTRY_STATUS_XRAY_ADDR" "$ENTRY_STATUS_XRAY_PORT" "$ENTRY_STATUS_XRAY_LISTEN_LINE")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}服务状态${PLAIN}" "${BOLD}Service status${PLAIN}" "${BOLD}Состояние обслуживания${PLAIN}")"
    echo -e "nginx：${ENTRY_STATUS_NGINX_SERVICE}"
    echo -e "$(localized_text "TCP Peek + Splice / vpso-mux 分流器：${ENTRY_STATUS_TCPPEEK_SERVICE}" "TCP Peek + Splice / vpso-mux routing: ${ENTRY_STATUS_TCPPEEK_SERVICE}" "TCP Peek + Splice / vpso-mux маршрутизация: ${ENTRY_STATUS_TCPPEEK_SERVICE}")"
    echo -e "Xray/3x-ui/x-ui：${ENTRY_STATUS_XRAY_SERVICE}"
}

show_current_entry_summary() {
    detect_current_entry_status
    echo -e "$(localized_text "${BOLD}当前入口模式：${CYAN}${ENTRY_STATUS_MODE}${PLAIN}" "${BOLD}Current entry mode: ${ENTRY_STATUS_MODE}${PLAIN}" "${BOLD}Текущий режим ввода: ${ENTRY_STATUS_MODE}${PLAIN}")"
    print_entry_mode_compat_notice
    if [[ "$ENTRY_STATUS_CONSISTENT" != "yes" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 配置模式与公网 443 实际监听不一致，详情看 [1]，建议确认后重新应用当前入口模式。${PLAIN}" "${YELLOW}⚠️ The configuration mode is inconsistent with the actual listening of public port 443. For details, see [1]. It is recommended to re-apply the current entry mode after confirmation.${PLAIN}" "${YELLOW}⚠️ Режим настройки не соответствует фактическому прослушиваниеу публичного порта 443. Подробности см. в [1]. После подтверждения рекомендуется повторно применить текущий режим входа.${PLAIN}")"
    fi
}
