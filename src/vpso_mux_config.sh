# shellcheck shell=bash
# vpso-mux YAML rendering and TCP Peek config generation.

append_vpso_mux_route_yaml() {
    local file="$1"
    local name="$2"
    local sni="$3"
    local backend="$4"
    local whitelist="$5"
    {
        echo "  - name: $(yaml_quote "$name")"
        echo "    sni:"
        echo "      - $(yaml_quote "$sni")"
        echo "    backend: $(yaml_quote "$backend")"
        if [[ -n "$whitelist" ]]; then
            echo "    whitelist:"
            local range
            for range in $whitelist; do
                echo "      - $(yaml_quote "$range")"
            done
        fi
    } >> "$file"
}

write_vpso_mux_config_from_sni_stack() {
    local listen_port="${1:-$NGINX_LISTEN_PORT}"
    local output_file="${2:-$(vpso_mux_config_path)}"
    local web_backend xray_backend listen_addr route_name ranges i domain backend
    web_backend=$(web_proxy_backend)
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    mkdir -p "$(dirname "$output_file")"

    {
        echo "listen:"
        echo "  tcp:"
        if [[ "$NGINX_LISTEN_ADDR" == "0.0.0.0" ]]; then
            echo "    - $(yaml_quote "0.0.0.0:${listen_port}")"
        elif [[ "$NGINX_LISTEN_ADDR" == "::" ]]; then
            echo "    - $(yaml_quote "[::]:${listen_port}")"
        else
            listen_addr=$(format_hostport "$NGINX_LISTEN_ADDR" "$listen_port")
            echo "    - $(yaml_quote "$listen_addr")"
        fi
        echo ""
        echo "timeouts:"
        echo "  peek: $(yaml_quote "3s")"
        echo "  dial: $(yaml_quote "5s")"
        echo "  idle: $(yaml_quote "300s")"
        echo "  shutdown: $(yaml_quote "10s")"
        echo ""
        echo "splice:"
        echo "  enabled: true"
        echo "  pipe_size: 1048576"
        echo "  fallback_to_copy: true"
        echo ""
        echo "limits:"
        echo "  max_connections: 4096"
        echo ""
        echo "default_backend: $(yaml_quote "$xray_backend")"
        echo ""
        echo "routes:"
    } > "$output_file"

    ranges=$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")
    append_vpso_mux_route_yaml "$output_file" "panel" "$PANEL_DOMAIN" "$web_backend" "$ranges"
    if [[ -z "$ranges" ]]; then
        echo -e "${YELLOW}⚠️ 面板域名 ${PANEL_DOMAIN} 当前未配置 IP 白名单；切换前请确认这是你想要的行为。${PLAIN}"
    fi

    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        route_name=$(sni_stack_route_name "site" "$domain")
        ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        append_vpso_mux_route_yaml "$output_file" "$route_name" "$domain" "$web_backend" "$ranges"
    done

    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        route_name=$(sni_stack_route_name "tcp" "$domain")
        backend=$(format_hostport "${TCP_ROUTE_ADDRS[$i]}" "${TCP_ROUTE_PORTS[$i]}")
        append_vpso_mux_route_yaml "$output_file" "$route_name" "$domain" "$backend" ""
    done

    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        route_name=$(sni_stack_route_name "xray" "$domain")
        backend=$(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}")
        append_vpso_mux_route_yaml "$output_file" "$route_name" "$domain" "$backend" ""
    done

    append_vpso_mux_route_yaml "$output_file" "reality" "$REALITY_SNI" "$xray_backend" ""

    cat <<EOF >> "$output_file"

logging:
  level: $(yaml_quote "info")
  format: $(yaml_quote "json")
EOF
    chmod 600 "$output_file" 2>/dev/null || true
}

generate_tcp_peek_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}重新应用 TCP Peek + Splice 配置${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}只生成 TCP Peek + Splice 分流规则，不改服务，不改端口，不接管 443。${PLAIN}"
    write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$(vpso_mux_config_path)" || return 1
    echo -e "${GREEN}✅ 已生成：$(vpso_mux_config_path)${PLAIN}"
    echo -e "默认后端：$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")"
    echo -e "Web 反代后端：$(web_proxy_engine_label) $(web_proxy_backend)"
    echo -e "${YELLOW}下一步建议先校验配置，再使用 TCP Peek + Splice 测试入口监听 8444。${PLAIN}"
}
