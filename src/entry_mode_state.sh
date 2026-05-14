# shellcheck shell=bash
# 443 entry mode state, listener detection, and compatibility helpers.

get_entry_mode() {
    local env_file="/etc/vps-optimize/sni-stack.env"
    local mode=""

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
            echo "nginx-stream"
            ;;
        "xray-fallback"|"xray_fallback")
            echo "xray-fallback"
            ;;
        "tcp-peek"|"tcp_peek")
            echo "tcp-peek"
            ;;
        *)
            echo "invalid:${mode}"
            ;;
    esac
}

print_entry_mode_compat_notice() {
    local env_file="/etc/vps-optimize/sni-stack.env"
    local state_file env_mode state_engine normalized
    state_file=$(single_443_engine_state_path 2>/dev/null || echo "/etc/vps-optimize/443-engine.conf")

    if [[ -f "$env_file" ]]; then
        env_mode=$(
            # shellcheck disable=SC1090
            unset ENTRY_MODE
            source "$env_file" 2>/dev/null || true
            printf '%s' "${ENTRY_MODE:-}"
        )
        if [[ -z "$env_mode" ]]; then
            echo -e "${YELLOW}兼容提示：${env_file} 未写 ENTRY_MODE，已按 nginx-stream 读取；下次保存会写入 ENTRY_MODE='nginx-stream'。${PLAIN}"
        else
            case "$env_mode" in
                "nginx_stream"|"xray_fallback"|"tcp_peek")
                    normalized=$(normalize_entry_mode_name "$env_mode" 2>/dev/null || echo "nginx-stream")
                    echo -e "${YELLOW}兼容提示：检测到旧 ENTRY_MODE='${env_mode}'，当前按 '${normalized}' 读取；下次保存会写入新命名。${PLAIN}"
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
                echo -e "${YELLOW}兼容提示：检测到旧 engine='${state_engine}'，当前按 '${normalized}' 读取；下次切换/重新应用会写入新命名。${PLAIN}"
                ;;
        esac
    fi
}

set_entry_mode() {
    local mode="$1"
    local env_file="/etc/vps-optimize/sni-stack.env"

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

    mkdir -p /etc/vps-optimize
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
        tcppeek) echo "TCP Peek + Splice 模式 (vpso-mux 分流器)" ;;
        caddy) echo "Caddy（不应直接接管 443 单入口）" ;;
        none) echo "未监听" ;;
        multiple) echo "多个进程监听/匹配" ;;
        unknown) echo "已监听，但进程不可见" ;;
        unknown:*) echo "未知进程 ${listener#unknown:}" ;;
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
        echo "未配置"
        return 0
    fi
    if [[ -z "$line" || "$line" == "未监听" || "$line" == "not-configured" ]]; then
        echo "未监听"
        return 0
    fi

    proc=$(listen_process_from_ss_line "$line")
    if [[ "$proc" == "unknown" ]]; then
        echo "已监听（进程不可见）"
    else
        echo "已监听（${proc}）"
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
    local env_file="/etc/vps-optimize/sni-stack.env"
    local listener_info expected_listener xui_svc xui_status

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
    ENTRY_STATUS_XRAY_SERVICE="面板托管 Xray: ${xui_status} / 独立 xray.service: $(service_status_compact xray)"
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
    echo -e "${BOLD}当前 443 入口状态${PLAIN}"
    echo -e "配置模式：${CYAN}${ENTRY_STATUS_MODE}${PLAIN}"
    print_entry_mode_compat_notice
    echo -e "公网 443：${ENTRY_STATUS_LISTENER_DISPLAY}"
    echo -e "监听进程：${ENTRY_STATUS_LISTENER_PROCESS}"
    if [[ "$ENTRY_STATUS_LISTENER" == "xray" ]]; then
        echo -e "Xray 公网：${GREEN}公网 443 当前由 Xray/面板托管 Xray 监听${PLAIN}"
    else
        echo -e "Xray 公网：未检测到 Xray 监听公网 443"
    fi
    if [[ "$ENTRY_STATUS_CONSISTENT" == "yes" ]]; then
        echo -e "一致性：${GREEN}配置模式与实际监听一致${PLAIN}"
    else
        echo -e "一致性：${YELLOW}配置模式与实际监听不一致${PLAIN}"
        echo -e "${YELLOW}配置模式与实际监听不一致，建议重新应用当前入口模式。${PLAIN}"
    fi
    echo -e "------------------------------------------------"
    echo -e "${BOLD}本地监听${PLAIN}"
    echo -e "Caddy：${ENTRY_STATUS_CADDY_ADDR}:${ENTRY_STATUS_CADDY_PORT} - $(listen_line_status "$ENTRY_STATUS_CADDY_ADDR" "$ENTRY_STATUS_CADDY_PORT" "$ENTRY_STATUS_CADDY_LISTEN_LINE")"
    echo -e "Xray： ${ENTRY_STATUS_XRAY_ADDR}:${ENTRY_STATUS_XRAY_PORT} - $(listen_line_status "$ENTRY_STATUS_XRAY_ADDR" "$ENTRY_STATUS_XRAY_PORT" "$ENTRY_STATUS_XRAY_LISTEN_LINE")"
    echo -e "------------------------------------------------"
    echo -e "${BOLD}服务状态${PLAIN}"
    echo -e "nginx：${ENTRY_STATUS_NGINX_SERVICE}"
    echo -e "TCP Peek + Splice / vpso-mux 分流器：${ENTRY_STATUS_TCPPEEK_SERVICE}"
    echo -e "Xray/3x-ui/x-ui：${ENTRY_STATUS_XRAY_SERVICE}"
}

show_current_entry_summary() {
    detect_current_entry_status
    echo -e "${BOLD}当前入口模式：${CYAN}${ENTRY_STATUS_MODE}${PLAIN}"
    print_entry_mode_compat_notice
    if [[ "$ENTRY_STATUS_CONSISTENT" != "yes" ]]; then
        echo -e "${YELLOW}⚠️ 配置模式与公网 443 实际监听不一致，详情看 [1]，建议确认后重新应用当前入口模式。${PLAIN}"
    fi
}
