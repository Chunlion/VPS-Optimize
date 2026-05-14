# shellcheck shell=bash
# 443 stack custom TCP-route CRUD workflows.

list_sni_stack_tcp_routes() {
    load_sni_stack_env || return 1
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}当前 443 TCP/SNI 本地入站分流${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "公网入口：${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT}"
    echo -e "REALITY 默认后端：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    echo -e "------------------------------------------------"
    if [[ ${#TCP_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有额外 TCP/SNI 入站分流。${PLAIN}"
        return 0
    fi

    local i num
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${TCP_ROUTE_SNIS[$i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$i]}:${TCP_ROUTE_PORTS[$i]}"
    done
}

add_sni_stack_tcp_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}新增 443 TCP/SNI 本地入站分流${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}用途：你已在 3x-ui 新增本地入站，本功能只把某个 SNI 通过公网 ${NGINX_LISTEN_PORT} 分流到该本地端口。${PLAIN}"
    echo -e "${YELLOW}要求：协议必须是 TCP 且客户端握手能带 SNI；UDP/QUIC/Hysteria2/TUIC 或无 SNI 的裸协议不适用。${PLAIN}"
    echo -e "${YELLOW}安全边界：后端只允许 127.0.0.1/localhost/::1，不会开放新公网端口。${PLAIN}"
    echo -e "------------------------------------------------"

    local route_sni route_addr route_port existing idx
    read_trimmed route_sni "请输入用于分流的新 SNI/域名（例如 relay.example.com）: "
    route_sni=$(normalize_domain_input "$route_sni")
    if [[ -z "$route_sni" || "$route_sni" == "0" ]]; then
        echo -e "${BLUE}已取消新增 TCP/SNI 入站。${PLAIN}"
        return 0
    fi
    is_valid_domain "$route_sni" || { echo -e "${RED}❌ SNI/域名格式无效。${PLAIN}"; return 1; }
    if [[ "$route_sni" == "$PANEL_DOMAIN" || "$route_sni" == "$REALITY_SNI" ]]; then
        echo -e "${RED}❌ TCP/SNI 入站域名不能和面板域名或 REALITY SNI 相同。${PLAIN}"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已作为网站/反代域名使用。${PLAIN}"; return 1; }
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该 TCP/SNI 入站已经存在。${PLAIN}"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已作为 Xray 入站使用。${PLAIN}"; return 1; }
    done

    check_domain_dns_sanity "$route_sni" "TCP/SNI 入站域名" "warn" || echo -e "${YELLOW}⚠️ 如果客户端使用服务器 IP 连接并手动指定 SNI，可忽略该 DNS 警告。${PLAIN}"
    route_addr=$(ask_with_default "3x-ui 新入站本地监听地址（只允许本地）" "127.0.0.1")
    route_addr=$(normalize_loopback_addr "$route_addr")
    route_port=$(ask_with_default "3x-ui 新入站本地监听端口" "8443")
    is_loopback_listen_addr "$route_addr" || { echo -e "${RED}❌ 为保证安全，TCP/SNI 入站后端只允许 127.0.0.1、localhost 或 ::1。${PLAIN}"; return 1; }
    is_valid_port "$route_port" || { echo -e "${RED}❌ 入站端口无效：${route_port}${PLAIN}"; return 1; }
    if [[ "$route_port" == "$NGINX_LISTEN_PORT" || "$route_port" == "$CADDY_LISTEN_PORT" || "$route_port" == "$PANEL_LISTEN_PORT" || "$route_port" == "$SUB_LISTEN_PORT" ]]; then
        echo -e "${RED}❌ 入站端口不能复用公网入口、Caddy、面板或订阅服务端口。${PLAIN}"
        return 1
    fi

    echo -e ""
    echo -e "${CYAN}即将添加 TCP/SNI 分流：${route_sni}:${NGINX_LISTEN_PORT} -> ${route_addr}:${route_port}${PLAIN}"
    echo -e "${YELLOW}请确认 3x-ui 入站已监听 ${route_addr}:${route_port}，且客户端连接端口使用 ${NGINX_LISTEN_PORT}。${PLAIN}"
    echo -e "${YELLOW}说明：Web 白名单只保护 Caddy/Web 域名，不会应用到 TCP/SNI 或 Xray 节点流量。${PLAIN}"
    confirm_risk_action "新增 443 TCP/SNI 入站 ${route_sni}" \
        "Nginx stream SNI 分流规则，会把该 SNI 直通到本地 3x-ui 入站" \
        "使用 443 单入口备份恢复，或从 TCP/SNI 入站管理菜单删除该分流" \
        "确认后端只监听本地地址，不要在安全组或防火墙开放 ${route_port}。" || return 1

    idx=${#TCP_ROUTE_SNIS[@]}
    TCP_ROUTE_SNIS[$idx]="$route_sni"
    TCP_ROUTE_ADDRS[$idx]="$route_addr"
    TCP_ROUTE_PORTS[$idx]="$route_port"
    save_and_offer_reapply_sni_stack
}

edit_sni_stack_tcp_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改 443 TCP/SNI 本地入站分流${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    if [[ ${#TCP_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可修改的 TCP/SNI 入站分流。${PLAIN}"
        return 0
    fi

    local i num choice idx old_sni new_sni new_addr new_port existing
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${TCP_ROUTE_SNIS[$i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$i]}:${TCP_ROUTE_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "请输入要修改的序号: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消修改。${PLAIN}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#TCP_ROUTE_SNIS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    old_sni="${TCP_ROUTE_SNIS[$idx]}"
    new_sni=$(normalize_domain_input "$(ask_with_default "SNI/域名" "$old_sni")")
    new_addr=$(ask_with_default "本地监听地址（只允许本地）" "${TCP_ROUTE_ADDRS[$idx]}")
    new_addr=$(normalize_loopback_addr "$new_addr")
    new_port=$(ask_with_default "本地监听端口" "${TCP_ROUTE_PORTS[$idx]}")

    is_valid_domain "$new_sni" || { echo -e "${RED}❌ SNI/域名格式无效。${PLAIN}"; return 1; }
    if [[ "$new_sni" == "$PANEL_DOMAIN" || "$new_sni" == "$REALITY_SNI" ]]; then
        echo -e "${RED}❌ TCP/SNI 入站域名不能和面板域名或 REALITY SNI 相同。${PLAIN}"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$new_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已作为网站/反代域名使用。${PLAIN}"; return 1; }
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        [[ "$new_sni" == "${TCP_ROUTE_SNIS[$i]}" ]] && { echo -e "${RED}❌ 该 TCP/SNI 入站已经存在。${PLAIN}"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$new_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已作为 Xray 入站使用。${PLAIN}"; return 1; }
    done
    is_loopback_listen_addr "$new_addr" || { echo -e "${RED}❌ 为保证安全，TCP/SNI 入站后端只允许 127.0.0.1、localhost 或 ::1。${PLAIN}"; return 1; }
    is_valid_port "$new_port" || { echo -e "${RED}❌ 入站端口无效：${new_port}${PLAIN}"; return 1; }
    if [[ "$new_port" == "$NGINX_LISTEN_PORT" || "$new_port" == "$CADDY_LISTEN_PORT" || "$new_port" == "$PANEL_LISTEN_PORT" || "$new_port" == "$SUB_LISTEN_PORT" ]]; then
        echo -e "${RED}❌ 入站端口不能复用公网入口、Caddy、面板或订阅服务端口。${PLAIN}"
        return 1
    fi

    echo -e ""
    echo -e "${CYAN}即将修改：${old_sni}:${NGINX_LISTEN_PORT} -> ${new_sni}:${NGINX_LISTEN_PORT} -> ${new_addr}:${new_port}${PLAIN}"
    confirm_risk_action "修改 443 TCP/SNI 入站 ${old_sni}" \
        "Nginx stream SNI 分流规则和本地后端端口" \
        "使用 443 单入口备份恢复修改前配置" \
        "确认 3x-ui 入站已按新地址和端口监听，且未开放该内部端口。" || return 1

    TCP_ROUTE_SNIS[$idx]="$new_sni"
    TCP_ROUTE_ADDRS[$idx]="$new_addr"
    TCP_ROUTE_PORTS[$idx]="$new_port"
    if [[ "$old_sni" != "$new_sni" ]]; then
        rename_sni_ip_whitelist_domain "$old_sni" "$new_sni"
    fi
    save_and_offer_reapply_sni_stack
}

remove_sni_stack_tcp_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}删除 443 TCP/SNI 本地入站分流${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    if [[ ${#TCP_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可删除的 TCP/SNI 入站分流。${PLAIN}"
        return 0
    fi

    local i num choice idx route_sni
    local -a new_snis=()
    local -a new_addrs=()
    local -a new_ports=()
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${TCP_ROUTE_SNIS[$i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$i]}:${TCP_ROUTE_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "请输入要删除的序号: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消删除。${PLAIN}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#TCP_ROUTE_SNIS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    route_sni="${TCP_ROUTE_SNIS[$idx]}"
    confirm_risk_action "从 443 分流中移除 TCP/SNI 入站 ${route_sni}" \
        "该 SNI 的 Nginx stream 直通规则" \
        "使用 443 单入口备份恢复，或重新新增该 TCP/SNI 入站" \
        "确认没有客户端仍依赖该 SNI 连接。" || return 1

    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_snis+=("${TCP_ROUTE_SNIS[$i]}")
        new_addrs+=("${TCP_ROUTE_ADDRS[$i]}")
        new_ports+=("${TCP_ROUTE_PORTS[$i]}")
    done
    TCP_ROUTE_SNIS=("${new_snis[@]}")
    TCP_ROUTE_ADDRS=("${new_addrs[@]}")
    TCP_ROUTE_PORTS=("${new_ports[@]}")
    remove_sni_ip_whitelist_for_domain "$route_sni"
    save_and_offer_reapply_sni_stack
}
