# shellcheck shell=bash
# Xray SNI route persistence and local listener status helpers.

xray_sni_routes_path() {
    echo "/etc/vps-optimize/xray-sni-routes.conf"
}

load_xray_sni_route_arrays() {
    local route_file line sni addr port
    route_file=$(xray_sni_routes_path)
    XRAY_SNI_ROUTE_SNIS=()
    XRAY_SNI_ROUTE_ADDRS=()
    XRAY_SNI_ROUTE_PORTS=()

    [[ -f "$route_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        [[ -n "$(trim_input "$line")" ]] || continue
        IFS='|' read -r sni addr port _ <<< "$line"
        sni=$(normalize_domain_input "$sni")
        addr=$(normalize_loopback_addr "${addr:-127.0.0.1}")
        port="$(trim_input "${port:-}")"
        if is_valid_domain "$sni" && is_loopback_listen_addr "$addr" && is_valid_port "$port"; then
            XRAY_SNI_ROUTE_SNIS+=("$sni")
            XRAY_SNI_ROUTE_ADDRS+=("$addr")
            XRAY_SNI_ROUTE_PORTS+=("$port")
        fi
    done < "$route_file"
}

save_xray_sni_route_arrays() {
    local route_file i
    route_file=$(xray_sni_routes_path)
    mkdir -p "$(dirname "$route_file")"
    : > "$route_file"
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ -n "${XRAY_SNI_ROUTE_SNIS[$i]:-}" ]] || continue
        printf '%s|%s|%s\n' "${XRAY_SNI_ROUTE_SNIS[$i]}" "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}" >> "$route_file"
    done
    chmod 600 "$route_file" 2>/dev/null || true
}

xray_sni_route_index() {
    local sni="$1"
    local i
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$sni" == "${XRAY_SNI_ROUTE_SNIS[$i]}" ]] && { echo "$i"; return 0; }
    done
    return 1
}

xray_fallback_main_route_index() {
    local i
    if [[ -n "${XRAY_FALLBACK_MAIN_SNI:-}" ]]; then
        for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            [[ "$XRAY_FALLBACK_MAIN_SNI" == "${XRAY_SNI_ROUTE_SNIS[$i]}" ]] && { echo "$i"; return 0; }
        done
    fi
    if [[ -n "${XRAY_FALLBACK_MAIN_ADDR:-}" && -n "${XRAY_FALLBACK_MAIN_PORT:-}" ]]; then
        for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            if [[ "$XRAY_FALLBACK_MAIN_ADDR" == "${XRAY_SNI_ROUTE_ADDRS[$i]}" && "$XRAY_FALLBACK_MAIN_PORT" == "${XRAY_SNI_ROUTE_PORTS[$i]}" ]]; then
                echo "$i"
                return 0
            fi
        done
    fi
    if [[ "$(get_entry_mode)" == "xray-fallback" && -n "${XRAY_LISTEN_ADDR:-}" && -n "${XRAY_LISTEN_PORT:-}" ]]; then
        for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            if [[ "$XRAY_LISTEN_ADDR" == "${XRAY_SNI_ROUTE_ADDRS[$i]}" && "$XRAY_LISTEN_PORT" == "${XRAY_SNI_ROUTE_PORTS[$i]}" ]]; then
                echo "$i"
                return 0
            fi
        done
    fi
    return 1
}

set_xray_fallback_main_route_from_index() {
    local idx="$1"
    [[ "$idx" =~ ^[0-9]+$ ]] || return 1
    (( idx >= 0 && idx < ${#XRAY_SNI_ROUTE_SNIS[@]} )) || return 1
    XRAY_FALLBACK_MAIN_SNI="${XRAY_SNI_ROUTE_SNIS[$idx]}"
    XRAY_FALLBACK_MAIN_ADDR="${XRAY_SNI_ROUTE_ADDRS[$idx]}"
    XRAY_FALLBACK_MAIN_PORT="${XRAY_SNI_ROUTE_PORTS[$idx]}"
}

print_xray_fallback_mode_explanation() {
    echo -e "${YELLOW}Xray 本身可以有多个入站。但在 xray-fallback 模式下，公网 443 默认由一个 Xray 主入站接管。脚本暂不支持在该模式下继续按多个 SNI 分流到多个本地 Xray 入站。${PLAIN}"
    echo -e "${YELLOW}该模式只负责 Xray 主入站监听公网 443，并 fallback 普通 HTTPS 到所选 Web 反代引擎。${PLAIN}"
    echo -e "${YELLOW}如需多个本地 Xray 入站通过 443 按 SNI 分流，请使用 Nginx Stream 模式或 TCP Peek + Splice 模式。${PLAIN}"
    echo -e "${YELLOW}如果 Web 域名开启 CDN/WAF/源站保护/Cloudflare 回源限制/Caddy 白名单，403 或拒绝访问通常是 Web/CDN/白名单/SNI 策略阻断，不一定是证书或 Caddy 故障。${PLAIN}"
}

print_xray_fallback_main_route_summary() {
    local idx
    idx=$(xray_fallback_main_route_index 2>/dev/null || true)
    if [[ -n "$idx" ]]; then
        echo -e "${GREEN}当前 xray-fallback 主入站：${XRAY_SNI_ROUTE_SNIS[$idx]} -> ${XRAY_SNI_ROUTE_ADDRS[$idx]}:${XRAY_SNI_ROUTE_PORTS[$idx]}${PLAIN}"
    elif [[ -n "${XRAY_FALLBACK_MAIN_SNI:-}" ]]; then
        echo -e "${YELLOW}当前 xray-fallback 主入站记录：${XRAY_FALLBACK_MAIN_SNI} -> ${XRAY_FALLBACK_MAIN_ADDR:-?}:${XRAY_FALLBACK_MAIN_PORT:-?}，但未匹配到现有规则。${PLAIN}"
    elif [[ "$(get_entry_mode)" == "xray-fallback" ]]; then
        echo -e "${YELLOW}当前未记录 xray-fallback 主入站；请确认 Xray 主入站已按当前模式监听公网 443。${PLAIN}"
    fi
}

select_xray_fallback_main_route_for_switch() {
    load_sni_stack_env || return 1
    local count choice idx
    count=${#XRAY_SNI_ROUTE_SNIS[@]}

    if [[ "$count" -eq 0 ]]; then
        echo -e "${YELLOW}未找到 $(xray_sni_routes_path) 中的 Xray 入站分流规则。${PLAIN}"
        echo -e "${YELLOW}切换到 xray-fallback 时，将由用户已配置的 Xray 主入站接管公网 443；脚本不会修改 3x-ui/Xray 入站内部配置。${PLAIN}"
        confirm_risk_action "继续切换到 xray-fallback" \
            "公网 443 将由 Xray 主入站接管，普通 HTTPS fallback 到所选 Web 反代引擎" \
            "取消切换，先在 Xray 入站管理中记录一个主入站候选" \
            "确认你已经在 3x-ui/Xray 中准备好将作为主入站的配置。" || return 1
        XRAY_FALLBACK_MAIN_SNI=""
        XRAY_FALLBACK_MAIN_ADDR=""
        XRAY_FALLBACK_MAIN_PORT=""
        return 0
    fi

    print_xray_fallback_mode_explanation
    echo -e "------------------------------------------------"
    if [[ "$count" -eq 1 ]]; then
        echo -e "${CYAN}检测到 1 条 Xray 入站分流规则，可作为 xray-fallback 主入站候选：${PLAIN}"
        echo -e "1. ${XRAY_SNI_ROUTE_SNIS[0]} -> ${XRAY_SNI_ROUTE_ADDRS[0]}:${XRAY_SNI_ROUTE_PORTS[0]}"
        confirm_risk_action "使用该规则作为 xray-fallback 主入站候选" \
            "该规则会被记录为 xray-fallback 主入站；其他模式下仍按 xray-sni-routes.conf 正常分流" \
            "取消切换，先确认 3x-ui/Xray 主入站配置" \
            "确认该本地入站就是你希望在 xray-fallback 模式下接管公网 443 的主入站。" || return 1
        set_xray_fallback_main_route_from_index 0
        return 0
    fi

    echo -e "${CYAN}检测到多条 Xray 入站分流规则，请选择其中一条作为 xray-fallback 主入站：${PLAIN}"
    for idx in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        echo -e "${GREEN}$((idx + 1)).${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$idx]} -> ${XRAY_SNI_ROUTE_ADDRS[$idx]}:${XRAY_SNI_ROUTE_PORTS[$idx]}"
    done
    echo -e "${RED}0. 取消切换${PLAIN}"
    read_trimmed choice "请选择 xray-fallback 主入站候选: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消切换到 xray-fallback。${PLAIN}"
        return 1
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > count )); then
        echo -e "${RED}❌ 序号无效，已取消切换。${PLAIN}"
        return 1
    fi
    set_xray_fallback_main_route_from_index "$((choice - 1))" || return 1
    echo -e "${GREEN}✅ 已选择 xray-fallback 主入站候选：${XRAY_FALLBACK_MAIN_SNI} -> ${XRAY_FALLBACK_MAIN_ADDR}:${XRAY_FALLBACK_MAIN_PORT}${PLAIN}"
}

xray_sni_route_port_conflict() {
    local addr="$1"
    local port="$2"
    local skip_idx="${3:-}"
    local i
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ -n "$skip_idx" && "$i" == "$skip_idx" ]] && continue
        if [[ "$addr" == "${XRAY_SNI_ROUTE_ADDRS[$i]}" && "$port" == "${XRAY_SNI_ROUTE_PORTS[$i]}" ]]; then
            echo "${XRAY_SNI_ROUTE_SNIS[$i]}"
            return 0
        fi
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        if [[ "$addr" == "${TCP_ROUTE_ADDRS[$i]}" && "$port" == "${TCP_ROUTE_PORTS[$i]}" ]]; then
            echo "旧 TCP/SNI:${TCP_ROUTE_SNIS[$i]}"
            return 0
        fi
    done
    return 1
}

xray_route_listen_line_by_addr_port() {
    local addr="$1"
    local port="$2"
    local host_regex
    case "$addr" in
        "127.0.0.1") host_regex='(127\.0\.0\.1|0\.0\.0\.0|\*)' ;;
        "::1") host_regex='(\[::1\]|\[::\]|\*)' ;;
        "localhost") host_regex='(127\.0\.0\.1|0\.0\.0\.0|\[::1\]|\[::\]|\*)' ;;
        *) host_regex=$(printf '%s' "$addr" | sed 's/[.[\*^$()+?{}|\\]/\\&/g') ;;
    esac
    ss -lntp 2>/dev/null | grep -E "${host_regex}:${port}[[:space:]]" | head -n1 || true
}

print_xray_route_port_status() {
    local sni="$1"
    local addr="$2"
    local port="$3"
    local line conflict

    echo -e "${CYAN}${sni}${PLAIN} -> ${addr}:${port}"
    if [[ "${CADDY_LISTEN_PORT:-}" == "$port" ]]; then
        echo -e "${RED}  ❌ 与 Web 反代引擎本地端口 ${CADDY_LISTEN_PORT} 冲突，请换一个本地入站端口。${PLAIN}"
    fi

    conflict=$(xray_sni_route_port_conflict "$addr" "$port" "$(xray_sni_route_index "$sni" 2>/dev/null || true)" || true)
    [[ -n "$conflict" ]] && echo -e "${YELLOW}  ⚠️ 与规则 ${conflict} 使用了相同的 ${addr}:${port}，请确认是否故意复用。${PLAIN}"

    line=$(xray_route_listen_line_by_addr_port "$addr" "$port")
    if [[ -n "$line" ]]; then
        echo -e "${GREEN}  ✅ 端口已监听：${line}${PLAIN}"
        if echo "$line" | grep -Eq '(^|[[:space:]])(0\.0\.0\.0|\*|\[::\]):'"${port}"'[[:space:]]'; then
            echo -e "${YELLOW}  ⚠️ 检测到可能监听在 0.0.0.0/[::]，存在公网暴露风险，建议改为 127.0.0.1。${PLAIN}"
        fi
    else
        echo -e "${YELLOW}  ⚠️ 未检测到 ${addr}:${port} 监听，请先去 3x-ui 创建并启用对应入站。${PLAIN}"
    fi
}
