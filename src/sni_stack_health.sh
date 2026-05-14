# shellcheck shell=bash
# 443 single-entry health checks, HTTP/TLS probes, and subscription hints.

print_443_health_status_code_hints() {
    echo -e "${BOLD}状态码提示${PLAIN}"
    echo -e "  - 403/401：可能是 Web 白名单、CDN/WAF、源站保护、Host/SNI 策略或后端鉴权。"
    echo -e "  - 502：可能是 Caddy 到后端端口不通。"
    echo -e "  - 525/526：可能是 CDN 到源站 TLS 或证书校验失败。"
    echo -e "  - 超时：可能是 443 监听、防火墙、安全组、入口服务异常。"
}

print_443_health_reality_notes() {
    echo -e "${BOLD}REALITY 检查提示${PLAIN}"
    echo -e "  - 不要要求 REALITY serverName/dest 加入 Caddy。"
    echo -e "  - 不要要求本机证书覆盖 REALITY serverName。"
    echo -e "  - REALITY 应检查外部目标站点是否真实可访问、TLS 特征是否稳定。"
    echo -e "  - 普通 TLS 节点和 REALITY 节点的 SNI/serverName 检查逻辑必须区分。"
}

print_web_domain_http_status() {
    local label="$1"
    local domain="$2"
    local path="${3:-/}"
    local url code

    [[ -n "$domain" ]] || return 0
    path=$(normalize_path_prefix "$path")
    url="https://${domain}${path}"

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${label}：${url} -> ${YELLOW}未检测，curl 未安装${PLAIN}"
        return 0
    fi

    code=$(curl -k -L -o /dev/null -sS --connect-timeout 6 --max-time 12 -w '%{http_code}' "$url" 2>/dev/null) || code="timeout"
    [[ -z "$code" || "$code" == "000" ]] && code="timeout"
    echo -e "${label}：${url} -> ${code}"
}

print_domain_cert_file_status() {
    local domain="$1"
    local cert key root_cert root_key

    [[ -n "$domain" ]] || return 0
    cert="/etc/caddy/certs/${domain}.crt"
    key="/etc/caddy/certs/${domain}.key"
    root_cert="/root/cert/${domain}.crt"
    root_key="/root/cert/${domain}.key"

    echo -e "${CYAN}${domain}${PLAIN}"
    [[ -s "$cert" ]] && echo -e "  ${GREEN}✅ 证书文件存在：${cert}${PLAIN}" || echo -e "  ${YELLOW}⚠️ 证书文件不存在或为空：${cert}${PLAIN}"
    [[ -s "$key" ]] && echo -e "  ${GREEN}✅ 私钥文件存在：${key}${PLAIN}" || echo -e "  ${YELLOW}⚠️ 私钥文件不存在或为空：${key}${PLAIN}"

    if [[ -L "$root_cert" && "$(readlink "$root_cert" 2>/dev/null)" == "$cert" && -e "$root_cert" ]]; then
        echo -e "  ${GREEN}✅ /root/cert 证书软链接正常：${root_cert} -> ${cert}${PLAIN}"
    else
        echo -e "  ${YELLOW}⚠️ /root/cert 证书软链接异常或不存在：${root_cert}${PLAIN}"
    fi

    if [[ -L "$root_key" && "$(readlink "$root_key" 2>/dev/null)" == "$key" && -e "$root_key" ]]; then
        echo -e "  ${GREEN}✅ /root/cert 私钥软链接正常：${root_key} -> ${key}${PLAIN}"
    else
        echo -e "  ${YELLOW}⚠️ /root/cert 私钥软链接异常或不存在：${root_key}${PLAIN}"
    fi
}

print_xray_route_health_list() {
    local mode="$1"
    local i sni addr port line main_idx status

    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未配置 Xray 入站分流规则：$(xray_sni_routes_path)${PLAIN}"
        return 0
    fi

    main_idx=$(xray_fallback_main_route_index 2>/dev/null || true)
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        sni="${XRAY_SNI_ROUTE_SNIS[$i]}"
        addr="${XRAY_SNI_ROUTE_ADDRS[$i]}"
        port="${XRAY_SNI_ROUTE_PORTS[$i]}"
        [[ -n "$sni" ]] || continue

        if [[ "$mode" == "xray-fallback" ]]; then
            if [[ -n "$main_idx" && "$i" == "$main_idx" ]]; then
                status="xray-fallback 主入站，当前模式生效"
            else
                status="已保留，当前 xray-fallback 模式下不生效"
            fi
        else
            status="当前模式支持按 SNI 分流"
        fi

        echo -e "${CYAN}${sni}${PLAIN} -> ${addr}:${port}（${status}）"
        if [[ "${CADDY_LISTEN_PORT:-}" == "$port" ]]; then
            echo -e "${RED}  ❌ 与 Caddy 本地端口 ${CADDY_LISTEN_PORT} 冲突。${PLAIN}"
        fi
        line=$(xray_route_listen_line_by_addr_port "$addr" "$port")
        if [[ -n "$line" ]]; then
            echo -e "${GREEN}  ✅ 端口已监听：${line}${PLAIN}"
            if echo "$line" | grep -Eq '(^|[[:space:]])(0\.0\.0\.0|\*|\[::\]):'"${port}"'[[:space:]]'; then
                echo -e "${YELLOW}  ⚠️ 检测到可能监听在 0.0.0.0/[::]，存在公网暴露风险，建议改为 127.0.0.1。${PLAIN}"
            fi
        else
            echo -e "${YELLOW}  ⚠️ 未检测到 ${addr}:${port} 监听，请先去 3x-ui 创建并启用对应入站。${PLAIN}"
        fi
    done
}

sni_stack_health_check_enhanced() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧪 443 链路体检增强${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    detect_current_entry_status

    local mode caddy_backend xray_backend panel_backend sub_backend site_backend route_count ranges i domain public_443_lines mux_config mux_service
    mode="$ENTRY_STATUS_MODE"
    caddy_backend=$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    panel_backend=$(format_hostport "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT")
    sub_backend=$(format_hostport "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT")
    mux_config=$(vpso_mux_config_path)
    mux_service="/etc/systemd/system/$(vpso_mux_service_name)"
    route_count=$((2 + ${#SITE_DOMAINS[@]} + ${#TCP_ROUTE_SNIS[@]} + ${#XRAY_SNI_ROUTE_SNIS[@]}))

    echo -e "${BOLD}入口状态${PLAIN}"
    echo -e "当前 ENTRY_MODE：${GREEN}${mode}${PLAIN}"
    print_entry_mode_compat_notice
    echo -e "实际公网 443 监听服务：${ENTRY_STATUS_LISTENER_PROCESS}"
    public_443_lines=$(ss -lntp 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || true)
    echo -e "${public_443_lines:-未监听或当前用户无权限查看进程}"
    if [[ "$ENTRY_STATUS_CONSISTENT" == "yes" ]]; then
        echo -e "配置模式与实际监听：${GREEN}一致${PLAIN}"
    else
        echo -e "配置模式与实际监听：${YELLOW}不一致${PLAIN}"
        echo -e "${YELLOW}配置模式与实际监听不一致，建议重新应用当前入口模式。${PLAIN}"
    fi
    echo -e "nginx 状态：${ENTRY_STATUS_NGINX_SERVICE}"
    echo -e "Xray/3x-ui 状态：${ENTRY_STATUS_XRAY_SERVICE}"
    echo -e "TCP Peek + Splice 状态：${ENTRY_STATUS_TCPPEEK_SERVICE}"
    echo -e "caddy 状态：$(service_status_compact caddy)"
    if [[ -f "$mux_config" ]]; then
        echo -e "TCP Peek + Splice 分流规则：${GREEN}存在 ${mux_config}${PLAIN}"
    else
        echo -e "TCP Peek + Splice 分流规则：${YELLOW}未找到 ${mux_config}${PLAIN}"
    fi
    if [[ -f "$mux_service" ]]; then
        echo -e "vpso-mux 分流器 systemd：${GREEN}存在 ${mux_service}${PLAIN}"
    else
        echo -e "vpso-mux 分流器 systemd：${YELLOW}未找到 ${mux_service}${PLAIN}"
    fi

    echo -e "------------------------------------------------"
    echo -e "${BOLD}本地监听${PLAIN}"
    echo -e "Caddy 本地监听端口：${caddy_backend}"
    get_listen_line_by_port "$CADDY_LISTEN_PORT" | grep -q "$CADDY_LISTEN_ADDR" && echo -e "${GREEN}✅ Caddy 期望监听 ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}${PLAIN}" || echo -e "${YELLOW}⚠️ Caddy 监听地址需确认：$(get_listen_line_by_port "$CADDY_LISTEN_PORT")${PLAIN}"
    echo -e "Xray 本地监听端口：${xray_backend}"
    get_listen_line_by_port "$XRAY_LISTEN_PORT" | grep -q "$XRAY_LISTEN_ADDR" && echo -e "${GREEN}✅ Xray 期望监听 ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}${PLAIN}" || echo -e "${YELLOW}⚠️ Xray 监听地址需确认：$(get_listen_line_by_port "$XRAY_LISTEN_PORT")${PLAIN}"
    if [[ "$ENTRY_STATUS_LISTENER" == "xray" ]]; then
        echo -e "Xray 公网监听端口：${GREEN}公网 443 当前由 Xray 监听${PLAIN}"
    else
        echo -e "Xray 公网监听端口：未检测到 Xray 监听公网 443"
    fi

    echo -e "------------------------------------------------"
    echo -e "${BOLD}Xray 入站分流规则${PLAIN}"
    if entry_mode_supports_xray_sni_routes "$mode"; then
        echo -e "当前入口模式是否支持 Xray 入站分流规则：${GREEN}支持${PLAIN}"
    else
        echo -e "当前入口模式是否支持 Xray 入站分流规则：${YELLOW}不支持/当前不生效${PLAIN}"
    fi
    if [[ "$mode" == "xray-fallback" ]]; then
        echo -e "${YELLOW}当前为 Xray Fallback 模式，Xray 入站管理中的多 SNI 分流规则不生效。${PLAIN}"
        echo -e "${YELLOW}如需多个本地 Xray 入站，请切换到 Nginx Stream 模式或 TCP Peek + Splice 模式。${PLAIN}"
        echo -e "${YELLOW}普通 HTTPS 流量会先进入 Xray，再 fallback 到 Caddy；403/拒绝访问通常优先排查 Web 白名单、CDN/WAF、源站保护、Cloudflare 回源限制或 Host/SNI 策略。${PLAIN}"
        print_xray_fallback_main_route_summary
    fi
    print_xray_route_health_list "$mode"

    echo -e "------------------------------------------------"
    echo -e "${BOLD}Web 域名白名单状态${PLAIN}"
    print_sni_ip_whitelist_summary
    echo -e "Xray 节点白名单：不支持/不启用"

    echo -e "------------------------------------------------"
    echo -e "${BOLD}证书文件与 /root/cert 软链接${PLAIN}"
    print_domain_cert_file_status "$PANEL_DOMAIN"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        print_domain_cert_file_status "$domain"
    done

    echo -e "------------------------------------------------"
    echo -e "${BOLD}Web 域名访问 HTTP 状态码${PLAIN}"
    print_web_domain_http_status "面板路径" "$PANEL_DOMAIN" "$PANEL_WEB_PATH"
    print_web_domain_http_status "普通订阅路径" "$PANEL_DOMAIN" "$SUB_URI_PATH"
    print_web_domain_http_status "Clash/Mihomo 路径" "$PANEL_DOMAIN" "$CLASH_URI_PATH"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        print_web_domain_http_status "网站域名" "$domain" "/"
    done
    print_443_health_status_code_hints

    echo -e "------------------------------------------------"
    echo -e "${BOLD}路由摘要${PLAIN}"
    echo -e "default_backend 当前指向：${xray_backend}"
    echo -e "routes 数量：${route_count}"
    echo -e "unknown SNI 策略：default_backend -> ${xray_backend}"
    ranges=$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")
    echo -e "web panel: ${PANEL_DOMAIN}${PANEL_WEB_PATH} -> Caddy ${caddy_backend} -> 面板后端 ${panel_backend}"
    echo -e "web subscription: ${PANEL_DOMAIN}${SUB_URI_PATH} -> Caddy ${caddy_backend} -> 订阅后端 ${sub_backend}"
    echo -e "web clash/mihomo: ${PANEL_DOMAIN}${CLASH_URI_PATH} -> Caddy ${caddy_backend} -> 订阅后端 ${sub_backend}"
    echo -e "route panel: ${PANEL_DOMAIN} -> ${caddy_backend} whitelist=$([[ -n "$ranges" ]] && echo yes || echo no)"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        site_backend=$(format_hostport "${SITE_BACKEND_ADDRS[$i]}" "${SITE_BACKEND_PORTS[$i]}")
        echo -e "web site: ${domain}/ -> Caddy ${caddy_backend} -> 网站后端 ${site_backend}"
        echo -e "route site: ${domain} -> ${caddy_backend} whitelist=$([[ -n "$ranges" ]] && echo yes || echo no)"
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        echo -e "route tcp: ${domain} -> $(format_hostport "${TCP_ROUTE_ADDRS[$i]}" "${TCP_ROUTE_PORTS[$i]}") whitelist=no（非 Web/Caddy 域名不启用白名单）"
    done
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        echo -e "route xray: ${domain} -> $(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}") whitelist=no"
    done
    echo -e "route reality: ${REALITY_SNI} -> ${xray_backend} whitelist=no"
    print_443_health_reality_notes

    echo -e "------------------------------------------------"
    echo -e "最近 20 行 vpso-mux 日志："
    journalctl -u vpso-mux -n 20 --no-pager 2>/dev/null || echo "未读取到 vpso-mux 日志。"
    echo -e "------------------------------------------------"
    echo -e "测试命令："
    echo -e "  openssl s_client -connect SERVER_IP:${NGINX_LISTEN_PORT} -servername ${PANEL_DOMAIN}"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  openssl s_client -connect SERVER_IP:${NGINX_LISTEN_PORT} -servername ${SITE_DOMAINS[0]}"
    echo -e "  openssl s_client -connect SERVER_IP:${NGINX_LISTEN_PORT} -servername random.example.com"
}

check_sni_stack_subscription_hint() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔎 订阅链接与 External Proxy 检查提示${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "请在 3x-ui 的 REALITY 入站里开启 External Proxy，并确保："
    echo -e "  类型：相同"
    echo -e "  地址：你的节点域名或服务器 IP"
    echo -e "  端口：${NGINX_LISTEN_PORT}"
    echo -e "${YELLOW}提示：本教程推荐 Cloudflare 灰云 / DNS only。REALITY 节点地址必须直连 VPS，可填灰云节点域名或服务器公网 IP。${PLAIN}"
    echo -e ""
    echo -e "复制节点链接后应该看到："
    echo -e "  vless://...@节点地址:${NGINX_LISTEN_PORT}?security=reality&sni=${REALITY_SNI}&..."
    echo -e ""
    echo -e "订阅公网入口应为："
    echo -e "  普通订阅：      https://${PANEL_DOMAIN}${SUB_URI_PATH}"
    echo -e "  Clash/Mihomo：  https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    echo -e "${YELLOW}不要把公网订阅地址写成 :${SUB_LISTEN_PORT}，该端口只给 Caddy 在本机访问。${PLAIN}"
    echo -e ""
    echo -e "${YELLOW}如果链接里还是 :${XRAY_LISTEN_PORT}，说明 3x-ui 订阅仍在输出本地入站端口，请回到入站设置检查 External Proxy。${PLAIN}"
}
