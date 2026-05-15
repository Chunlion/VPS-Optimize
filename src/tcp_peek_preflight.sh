# shellcheck shell=bash
# TCP Peek preflight service, dry-run, and test-port workflows.

vpso_mux_preflight_config_path() {
    echo "/etc/vps-optimize/vpso-mux.preflight.yaml"
}

write_vpso_mux_preflight_service() {
    cat <<'EOF' > /etc/systemd/system/vpso-mux-preflight.service
[Unit]
Description=VPS-Optimize TCP Peek preflight router on 8444
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vpso-mux -config /etc/vps-optimize/vpso-mux.preflight.yaml
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 /etc/systemd/system/vpso-mux-preflight.service
    systemctl daemon-reload >/dev/null 2>&1 || true
}

port_listener_has_process() {
    local port="$1"
    local proc_pattern="$2"
    ss -lntp 2>/dev/null | grep -E "(:${port}[[:space:]]|:${port}$)" | grep -q "$proc_pattern"
}

tcppeek_preflight_probe_route_matrix() {
    local test_port="$1"
    local connect_host domain i route_addr route_port failures=0
    connect_host=$(probe_host_for_listen_addr "$NGINX_LISTEN_ADDR")

    echo -e "${CYAN}▶ 检查 TCP Peek 8444 路由矩阵...${PLAIN}"
    probe_tls_sni_certificate "TCP Peek 8444 面板 SNI 预检" "$connect_host" "$test_port" "$PANEL_DOMAIN" || failures=1

    for domain in "${SITE_DOMAINS[@]}"; do
        [[ -n "$domain" ]] || continue
        probe_tls_sni_certificate "TCP Peek 8444 Web SNI 预检 ${domain}" "$connect_host" "$test_port" "$domain" || failures=1
    done

    tcp_probe_host "TCP Peek 默认 Xray/REALITY 后端" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 3 1 || failures=1

    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        route_addr="${TCP_ROUTE_ADDRS[$i]}"
        route_port="${TCP_ROUTE_PORTS[$i]}"
        [[ -n "$domain" && -n "$route_addr" && -n "$route_port" ]] || continue
        tcp_probe_host "TCP Peek 本地 TCP/SNI 后端 ${domain}" "$(probe_host_for_listen_addr "$route_addr")" "$route_port" 3 1 || failures=1
    done

    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        route_addr="${XRAY_SNI_ROUTE_ADDRS[$i]}"
        route_port="${XRAY_SNI_ROUTE_PORTS[$i]}"
        [[ -n "$domain" && -n "$route_addr" && -n "$route_port" ]] || continue
        tcp_probe_host "TCP Peek Xray SNI 后端 ${domain}" "$(probe_host_for_listen_addr "$route_addr")" "$route_port" 3 1 || failures=1
    done

    if [[ "$failures" -ne 0 ]]; then
        echo -e "${RED}❌ TCP Peek 8444 路由矩阵预检失败，公网 443 未改动。${PLAIN}"
        return 1
    fi
    echo -e "${GREEN}✅ TCP Peek 8444 路由矩阵预检通过。${PLAIN}"
    return 0
}

run_tcppeek_preflight_service() {
    local keep_running="${1:-0}"
    local test_port="${2:-8444}"
    local config_file tmp_config
    config_file=$(vpso_mux_preflight_config_path)

    require_vpso_mux_binary_for_cutover || return 1
    tmp_config="${config_file}.tmp.$$"
    write_vpso_mux_config_from_sni_stack "$test_port" "$tmp_config" || return 1
    if ! run_vpso_mux_config_check "$tmp_config"; then
        quarantine_path "$tmp_config" "/etc/vps-optimize/quarantine/vpso-mux" >/dev/null 2>&1 || true
        return 1
    fi
    mv "$tmp_config" "$config_file" || return 1
    write_vpso_mux_preflight_service
    systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
    if ! systemctl start vpso-mux-preflight; then
        echo -e "${RED}❌ TCP Peek 8444 预检服务启动失败，公网 443 未改动。${PLAIN}"
        return 1
    fi
    sleep 1
    if ! port_listener_has_process "$test_port" 'vpso-mux'; then
        systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
        echo -e "${RED}❌ TCP Peek 8444 预检未监听到 vpso-mux，拒绝切换公网 443。${PLAIN}"
        return 1
    fi
    tcppeek_preflight_probe_route_matrix "$test_port" || {
        systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
        return 1
    }
    if [[ "$keep_running" != "1" ]]; then
        systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
    fi
    return 0
}

tcp_peek_dry_run_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}TCP Peek + Splice 分流规则校验${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    local config_file
    config_file=$(vpso_mux_config_path)
    [[ -f "$config_file" ]] || { echo -e "${YELLOW}未找到 ${config_file}，正在先生成配置。${PLAIN}"; write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$config_file" || return 1; }
    echo -e "${CYAN}▶ 校验 YAML、SNI、backend、whitelist 和重复 SNI...${PLAIN}"
    run_vpso_mux_config_check "$config_file" || return 1
    echo -e "${CYAN}▶ 检查本地后端端口...${PLAIN}"
    tcp_probe_host "Caddy 127.0.0.1:${CADDY_LISTEN_PORT}" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || true
    tcp_probe_host "Xray/REALITY 127.0.0.1:${XRAY_LISTEN_PORT}" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" || true
    print_sni_ip_whitelist_summary
    echo -e "${GREEN}✅ 配置校验完成。请先使用 TCP Peek + Splice 测试入口验证，不要直接接管 443。${PLAIN}"
}

start_tcp_peek_test_port() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}TCP Peek + Splice 状态 / 测试入口${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    if ! load_sni_stack_env; then
        NGINX_LISTEN_PORT="${NGINX_LISTEN_PORT:-443}"
        show_vpso_mux_runtime_status
        return 1
    fi
    show_vpso_mux_runtime_status
    echo -e "------------------------------------------------"
    if [[ "$(single_443_current_engine)" == "tcp-peek" ]]; then
        echo -e "${YELLOW}当前入口已经是 TCP Peek + Splice 模式。为避免误停公网 443，本入口不覆盖运行中的 443 配置。${PLAIN}"
        return 0
    fi
    echo -e "${YELLOW}vpso-mux 预检服务只监听 8444，当前公网 443 入口不会被停止或替换。${PLAIN}"
    confirm_risk_action "安装/构建 vpso-mux 并启动 8444 预检" \
        "可能安装 Go 工具链、构建 /usr/local/bin/vpso-mux，并启动独立 vpso-mux-preflight.service 监听 8444" \
        "停止 vpso-mux-preflight.service，或继续使用 Nginx Stream / Xray Fallback，不会改动公网 443" \
        "低内存或低磁盘机器会被资源预检查拦截；公网 443 在本步骤不会被替换。" || return 1
    install_vpso_mux_binary || return 1
    ensure_caddy_local_base_config || return 1
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    tcp_probe_host "Xray/REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1 || return 1
    run_tcppeek_preflight_service 1 "8444" || return 1
    echo -e "${GREEN}✅ vpso-mux 预检服务已启动在测试端口 8444，公网 443 未改动。${PLAIN}"
    echo -e "测试命令："
    echo -e "  openssl s_client -connect SERVER_IP:8444 -servername ${PANEL_DOMAIN}"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  openssl s_client -connect SERVER_IP:8444 -servername ${SITE_DOMAINS[0]}"
    echo -e "  openssl s_client -connect SERVER_IP:8444 -servername random.example.com"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  curl -vk --resolve ${SITE_DOMAINS[0]}:8444:SERVER_IP https://${SITE_DOMAINS[0]}:8444/"
}

preflight_tcppeek_before_cutover() {
    echo -e "${CYAN}▶ 正在执行 TCP Peek 8444 安全预检，公网 443 暂不改动...${PLAIN}"
    require_vpso_mux_binary_for_cutover || return 1
    warn_if_public_bind "Caddy" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    ensure_caddy_local_base_config || return 1
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    tcp_probe_host "Xray/REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1 || {
        echo -e "${RED}❌ Xray 本地入站不可达，拒绝切换 TCP Peek。请先在 3x-ui/Xray 中准备本地监听入站。${PLAIN}"
        return 1
    }
    run_tcppeek_preflight_service 0 "8444" || return 1
    echo -e "${GREEN}✅ TCP Peek 8444 预检通过，才会进入公网 443 切换。${PLAIN}"
}

preflight_entry_mode_before_cutover() {
    local target_mode="$1"
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1
    case "$target_mode" in
        "tcp-peek") preflight_tcppeek_before_cutover ;;
        *) return 0 ;;
    esac
}
