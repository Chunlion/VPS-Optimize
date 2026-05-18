# shellcheck shell=bash
# vpso-mux paths, engine state, route summaries, and runtime status output.

vpso_mux_config_path() {
    echo "/etc/vps-optimize/vpso-mux.yaml"
}

vpso_mux_service_name() {
    echo "vpso-mux.service"
}

vpso_mux_status_json_path() {
    echo "/var/lib/vps-optimize/vpso-mux/status.json"
}

single_443_engine_state_path() {
    echo "/etc/vps-optimize/443-engine.conf"
}

yaml_quote() {
    local value="$1"
    value=$(printf '%s' "$value" | sed "s/'/''/g")
    printf "'%s'" "$value"
}

single_443_current_engine() {
    local state_file raw_engine env_mode normalized
    state_file=$(single_443_engine_state_path)
    if [[ -f "$state_file" ]]; then
        raw_engine=$(
            # shellcheck disable=SC1090
            unset engine
            source "$state_file" 2>/dev/null || true
            printf '%s' "${engine:-}"
        )
        if [[ -n "$raw_engine" ]]; then
            normalized=$(normalize_entry_mode_name "$raw_engine" 2>/dev/null || true)
            if [[ -n "$normalized" ]]; then
                printf '%s' "$normalized"
            else
                printf 'invalid:%s' "$raw_engine"
            fi
            return 0
        fi
    fi
    env_mode=$(get_entry_mode)
    case "$env_mode" in
        "nginx-stream"|"xray-fallback"|"tcp-peek") printf '%s' "$env_mode" ;;
        *) printf 'nginx-stream' ;;
    esac
}

sni_stack_route_name() {
    local prefix="$1"
    local sni="$2"
    sni=$(echo "$sni" | tr '.-' '__' | tr -cd 'a-zA-Z0-9_')
    printf '%s_%s' "$prefix" "$sni"
}

sni_stack_route_summary_for_state() {
    local web_backend xray_backend summary i domain
    web_backend=$(web_proxy_backend)
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    summary="panel:${PANEL_DOMAIN}->${web_backend},reality:${REALITY_SNI}->${xray_backend},default->${xray_backend}"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] && summary+=",site:${domain}->${web_backend}"
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] && summary+=",tcp:${domain}->$(format_hostport "${TCP_ROUTE_ADDRS[$i]}" "${TCP_ROUTE_PORTS[$i]}")"
    done
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] && summary+=",xray:${domain}->$(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}")"
    done
    printf '%s' "$summary"
}

sni_stack_whitelist_summary_for_state() {
    local summary="" i
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        [[ -n "${SNI_IP_WHITELIST_DOMAINS[$i]}" && -n "${SNI_IP_WHITELIST_RANGES[$i]}" ]] || continue
        [[ -n "$summary" ]] && summary+="|"
        summary+="${SNI_IP_WHITELIST_DOMAINS[$i]}:${SNI_IP_WHITELIST_RANGES[$i]}"
    done
    printf '%s' "$summary"
}

write_single_443_engine_state() {
    local selected_engine="$1"
    local selected_engine_raw="$1"
    local backup_id="${2:-}"
    local state_file mux_config mux_service web_backend xray_backend routes whitelist_rules web_engine
    selected_engine=$(normalize_entry_mode_name "$selected_engine_raw") || { echo -e "${RED}Invalid engine: ${selected_engine_raw}${PLAIN}"; return 1; }
    state_file=$(single_443_engine_state_path)
    mux_config=$(vpso_mux_config_path)
    mux_service=$(vpso_mux_service_name)
    web_engine=$(current_web_proxy_engine)
    web_backend=$(web_proxy_backend)
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    routes=$(sni_stack_route_summary_for_state)
    whitelist_rules=$(sni_stack_whitelist_summary_for_state)
    [[ -z "$backup_id" ]] && backup_id=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null || true)

    mkdir -p /etc/vps-optimize
    cat <<EOF > "$state_file"
engine='${selected_engine}'
listen_addr='${NGINX_LISTEN_ADDR}'
listen_port='${NGINX_LISTEN_PORT}'
web_proxy_engine='${web_engine}'
web_proxy_backend='${web_backend}'
caddy_backend='${web_backend}'
xray_backend='${xray_backend}'
default_backend='${xray_backend}'
routes='${routes}'
whitelist_rules='${whitelist_rules}'
last_backup_id='${backup_id}'
mux_config_path='${mux_config}'
mux_systemd_service_name='${mux_service}'
EOF
    chmod 600 "$state_file" 2>/dev/null || true
}

show_single_443_engine_status() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔎 当前 443 入口状态 / 单入口引擎${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    local engine state_file mux_config
    engine=$(single_443_current_engine)
    state_file=$(single_443_engine_state_path)
    mux_config=$(vpso_mux_config_path)
    show_current_entry_status
    echo -e "------------------------------------------------"
    echo -e "当前 engine：${GREEN}${engine}${PLAIN}"
    echo -e "状态文件：${state_file}"
    echo -e "mux 配置：${mux_config}"
    echo -e "------------------------------------------------"
    echo -e "${GREEN}Nginx Stream 模式是默认稳定模式。${PLAIN}"
    echo -e "${YELLOW}TCP Peek + Splice 模式适合需要四层 SNI 分流和 splice 转发优化的进阶用户。${PLAIN}"
    echo -e "${YELLOW}首次建议先监听 8444 测试，不要直接接管 443。${PLAIN}"
    echo -e "${YELLOW}切换前会自动备份，可回滚。${PLAIN}"
    echo -e "------------------------------------------------"
    if [[ -f /etc/vps-optimize/sni-stack.env ]]; then
        load_sni_stack_env >/dev/null 2>&1 && print_sni_stack_current_summary
    else
        echo -e "${YELLOW}未检测到 sni-stack.env，尚未完成 443 单入口初始化。${PLAIN}"
    fi
    echo -e "------------------------------------------------"
    echo -e "公网 443 监听："
    ss -lntup 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || echo "未监听或当前用户无权限查看进程"
}

show_tcp_peek_splice_info() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}TCP Peek + Splice 模式${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}TCP Peek + Splice 模式：基于 MSG_PEEK 读取 TLS ClientHello 中的 SNI，不消费首包，并根据 SNI 将连接分流到 Caddy 或 Xray 本地后端；转发时优先使用 splice 零拷贝，失败时自动回退普通 copy。实际运行的分流器程序为 vpso-mux。${PLAIN}"
    echo -e "它只在 TCP 层读取 TLS ClientHello 的 SNI，不终止 TLS，不管理证书，不替换 Caddy，也不是 Xray 直占 443。"
    echo -e "推荐流程："
    echo -e "  1. 先生成 TCP Peek + Splice 分流规则：/etc/vps-optimize/vpso-mux.yaml"
    echo -e "  2. 校验配置和后端端口"
    echo -e "  3. 使用 TCP Peek + Splice 测试入口监听 8444"
    echo -e "  4. 确认后再事务式切换公网 443"
    echo -e "  5. 异常时从菜单回滚到 Nginx Stream 模式"
}

print_vpso_mux_systemd_fallback_status() {
    local listen_port="${1:-${NGINX_LISTEN_PORT:-443}}"
    local public_lines preflight_lines
    echo -e "${YELLOW}status.json 不存在或解析失败，已降级为 systemd / 监听状态检查。${PLAIN}"
    echo -e "vpso-mux：$(service_status_compact vpso-mux)"
    echo -e "vpso-mux-preflight：$(service_status_compact vpso-mux-preflight)"
    echo -e "公网 ${listen_port} 监听："
    public_lines=$(ss -lntp 2>/dev/null | awk -v p=":${listen_port}" '$4 ~ p"$" {print}' || true)
    echo "${public_lines:-未监听或当前用户无权限查看进程}"
    echo -e "8444 预检监听："
    preflight_lines=$(ss -lntp 2>/dev/null | awk '$4 ~ ":8444$" {print}' || true)
    echo "${preflight_lines:-未监听或当前用户无权限查看进程}"
}

print_vpso_mux_status_json() {
    local status_file py_bin
    status_file=$(vpso_mux_status_json_path)
    [[ -s "$status_file" ]] || return 1

    if command -v python3 >/dev/null 2>&1; then
        py_bin="python3"
    elif command -v python >/dev/null 2>&1; then
        py_bin="python"
    else
        return 1
    fi

    "$py_bin" - "$status_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

def value(name, default=0):
    return data.get(name, default)

print(f"status.json：{path}")
print(f"启动时间：{value('start_time', 'unknown')}")
print(f"更新时间：{value('updated_at', 'unknown')}")
listen = data.get("listen_addresses") or []
print("监听地址：" + (", ".join(listen) if listen else "unknown"))
max_connections = value('max_connections', 'unlimited')
if max_connections == 0:
    max_connections = 'unlimited'
print(f"连接上限：{max_connections}")
print(f"当前连接数：{value('active_connections')}")
print(f"连接总数：{value('total_connections')}")
print(f"拒绝连接数：{value('rejected_connections')}")
print(f"后端拨号错误：{value('backend_dial_errors')}")
print(f"splice 成功次数：{value('splice_success')}")
print(f"copy fallback 次数：{value('copy_fallback')}")
print(f"白名单拦截次数：{value('whitelist_blocked')}")
print(f"no_sni 次数：{value('no_sni')}")
print(f"peek 错误次数：{value('peek_errors')}")
print(f"peek 超时次数：{value('peek_timeouts')}")
print(f"客户端->后端字节：{value('bytes_client_to_backend')}")
print(f"后端->客户端字节：{value('bytes_backend_to_client')}")

route_hits = data.get("route_hits") or {}
print("按 route 命中次数：")
if route_hits:
    for name, count in sorted(route_hits.items(), key=lambda item: (-int(item[1]), item[0])):
        print(f"  - {name}: {count}")
else:
    print("  - 暂无")

recent_errors = data.get("recent_errors") or []
print("最近错误：")
if recent_errors:
    for item in recent_errors[-10:]:
        at = item.get("time", "unknown")
        msg = item.get("message", "")
        route = item.get("route_name", "")
        sni = item.get("sni", "")
        suffix = ""
        if route:
            suffix += f" route={route}"
        if sni:
            suffix += f" sni={sni}"
        print(f"  - {at} {msg}{suffix}")
else:
    print("  - 暂无")
PY
}

show_vpso_mux_runtime_status() {
    local status_file
    status_file=$(vpso_mux_status_json_path)
    echo -e "${BOLD}TCP Peek + Splice 运行统计${PLAIN}"
    if ! print_vpso_mux_status_json; then
        print_vpso_mux_systemd_fallback_status "${NGINX_LISTEN_PORT:-443}"
    fi
    echo -e "------------------------------------------------"
    echo -e "配置文件：$(vpso_mux_config_path)"
    echo -e "systemd：/etc/systemd/system/$(vpso_mux_service_name)"
    echo -e "状态文件：${status_file}"
}
