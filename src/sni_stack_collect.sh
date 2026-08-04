# shellcheck shell=bash
# Interactive 443 stack configuration collection.

collect_sni_stack_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}443 单入口共享配置${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}公网 443 将由你选择的入口模式监听；Web 域名、Web 反代引擎、证书和白名单为三种模式共享。${PLAIN}"
    echo -e "${YELLOW}Caddy/Xray/3x-ui 本地后端默认绑定 127.0.0.1。${PLAIN}"
    echo -e "------------------------------------------------"

    read_trimmed PANEL_DOMAIN "面板域名（必填，例如 panel.example.com）: "
    SITE_DOMAINS=()
    SITE_BACKEND_ADDRS=()
    SITE_BACKEND_PORTS=()
    TCP_ROUTE_SNIS=()
    TCP_ROUTE_ADDRS=()
    TCP_ROUTE_PORTS=()
    SNI_IP_WHITELIST_DOMAINS=()
    SNI_IP_WHITELIST_RANGES=()
    local site_domains_input
    site_domains_input=$(ask_with_default "网站/反代域名（可选，多个用英文逗号分隔，例如 site1.example.com,site2.example.com）" "")
    split_csv_to_array "$site_domains_input" SITE_DOMAINS
    echo -e "${YELLOW}REALITY 伪装 SNI 请填写外部真实 HTTPS 站点域名，不要填写面板域名或节点域名。${PLAIN}"
    echo -e "${YELLOW}模板示例：your-reality-sni.example.com（请替换成你自己选择的真实站点）${PLAIN}"
    read_trimmed REALITY_SNI "REALITY 伪装 SNI（必填）: "
    NGINX_LISTEN_ADDR=$(ask_with_default "Nginx 公网监听地址" "0.0.0.0")
    NGINX_LISTEN_PORT=$(ask_with_default "Nginx 公网监听端口" "443")

    local advanced_mode
    read_trimmed advanced_mode "是否进入高级模式并允许修改本地服务监听地址？(Y/n，默认 y): "
    if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
        CADDY_LISTEN_ADDR=$(ask_with_default "Caddy 本地监听地址" "127.0.0.1")
        XRAY_LISTEN_ADDR=$(ask_with_default "Xray REALITY 本地监听地址" "127.0.0.1")
        PANEL_LISTEN_ADDR=$(ask_with_default "3x-ui 面板监听地址" "127.0.0.1")
        SUB_LISTEN_ADDR=$(ask_with_default "3x-ui 订阅服务监听地址" "127.0.0.1")
    else
        CADDY_LISTEN_ADDR="127.0.0.1"
        XRAY_LISTEN_ADDR="127.0.0.1"
        PANEL_LISTEN_ADDR="127.0.0.1"
        SUB_LISTEN_ADDR="127.0.0.1"
        echo -e "${GREEN}普通模式：Caddy/Xray/3x-ui/订阅/网站后端均使用 127.0.0.1。${PLAIN}"
    fi

    CADDY_LISTEN_PORT=$(ask_with_default "Caddy 本地监听端口" "8443")
    XRAY_LISTEN_PORT=$(ask_with_default "Xray REALITY 本地监听端口" "1443")
    PANEL_LISTEN_PORT=$(ask_with_default "3x-ui 面板端口" "40000")
    PANEL_WEB_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui 面板公网路径 / webBasePath（必须和面板 url 根路径一致）" "/panel/")")
    SUB_LISTEN_PORT=$(ask_with_default "3x-ui 订阅服务端口（可自定义）" "2096")
    SUB_URI_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui 普通订阅路径前缀（不带端口和客户端 Subscription，建议写 /sub/）" "/sub/")")
    CLASH_URI_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui Clash/Mihomo 订阅路径前缀（不带客户端 Subscription，建议写 /clash/）" "/clash/")")
    local panel_whitelist_enabled panel_whitelist_input panel_whitelist_ranges current_client_ip
    local -a panel_whitelist_array=()
    read_trimmed panel_whitelist_enabled "是否为面板域名启用 IP 白名单？(Y/n，默认 y): "
    if [[ "$panel_whitelist_enabled" =~ ^[Yy]$ ]]; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
        read_trimmed panel_whitelist_input "请输入允许访问面板域名的 IP/CIDR（多个用空格或英文逗号分隔）: "
        normalize_ip_whitelist_input "$panel_whitelist_input" panel_whitelist_array || return 1
        append_vps_public_ips_to_whitelist panel_whitelist_array
        panel_whitelist_ranges=$(join_array_by_space "${panel_whitelist_array[@]}")
    fi
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i default_site_port
        default_site_port=3000
        for i in "${!SITE_DOMAINS[@]}"; do
            if [[ -z "${SITE_DOMAINS[$i]}" ]]; then
                continue
            fi
            if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
                SITE_BACKEND_ADDRS[$i]=$(ask_with_default "网站 ${SITE_DOMAINS[$i]} 的后端地址" "127.0.0.1")
            else
                SITE_BACKEND_ADDRS[$i]="127.0.0.1"
            fi
            SITE_BACKEND_PORTS[$i]=$(ask_with_default "网站 ${SITE_DOMAINS[$i]} 的后端端口" "$default_site_port")
            default_site_port=$((default_site_port + 1))
        done
    fi

    echo -e "${YELLOW}请确认 3x-ui 面板设置 -> 常规 -> 证书、订阅设置 -> 证书 路径已经清空。${PLAIN}"
    echo -e "${YELLOW}本向导会让 Caddy 通过 HTTP 连接 ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} 和 ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}。${PLAIN}"
    local cert_clear_confirm
    read_trimmed cert_clear_confirm "确认已经清空面板证书和订阅证书路径？(Y/n): "
    is_yes "$cert_clear_confirm" || { echo -e "${YELLOW}请先回 3x-ui 清空证书路径并保存重启，再运行本向导。${PLAIN}"; return 1; }

    echo -e "${CYAN}请输入 Cloudflare API Token（需 Zone.DNS.Edit + Zone.Zone.Read）${PLAIN}"
    read_secret_trimmed CF_TOKEN "CF Token: "

    PANEL_DOMAIN=$(normalize_domain_input "$PANEL_DOMAIN")
    REALITY_SNI=$(normalize_domain_input "$REALITY_SNI")
    local site_idx
    for site_idx in "${!SITE_DOMAINS[@]}"; do
        SITE_DOMAINS[$site_idx]=$(normalize_domain_input "${SITE_DOMAINS[$site_idx]}")
        SITE_BACKEND_ADDRS[$site_idx]=$(normalize_backend_addr_input "${SITE_BACKEND_ADDRS[$site_idx]:-127.0.0.1}")
    done

    if ! is_valid_domain "$PANEL_DOMAIN"; then echo -e "${RED}❌ 面板域名无效。${PLAIN}"; return 1; fi
    if ! is_valid_domain "$REALITY_SNI"; then echo -e "${RED}❌ REALITY SNI 无效。${PLAIN}"; return 1; fi
    check_domain_dns_sanity "$PANEL_DOMAIN" "面板域名" "prompt" || return 1
    check_domain_dns_sanity "$REALITY_SNI" "REALITY SNI" "prompt" || return 1
    local site_domain seen_domains
    seen_domains=" ${PANEL_DOMAIN} ${REALITY_SNI} "
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ -z "$site_domain" ]] && continue
        if ! is_valid_domain "$site_domain"; then echo -e "${RED}❌ 网站/反代域名无效：${site_domain}${PLAIN}"; return 1; fi
        if [[ "$site_domain" == "$PANEL_DOMAIN" || "$site_domain" == "$REALITY_SNI" || "$seen_domains" == *" ${site_domain} "* ]]; then
            echo -e "${RED}❌ 面板域名、网站/反代域名、REALITY SNI 不能相同：${site_domain}${PLAIN}"
            return 1
        fi
        check_domain_dns_sanity "$site_domain" "网站/反代域名" "prompt" || return 1
        seen_domains+=" ${site_domain} "
    done

    local p a
    for p in "$NGINX_LISTEN_PORT" "$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT" "${SITE_BACKEND_PORTS[@]}"; do
        is_valid_port "$p" || { echo -e "${RED}❌ 端口无效：${p}${PLAIN}"; return 1; }
    done
    for a in "$NGINX_LISTEN_ADDR" "$CADDY_LISTEN_ADDR" "$XRAY_LISTEN_ADDR" "$PANEL_LISTEN_ADDR" "$SUB_LISTEN_ADDR"; do
        is_valid_listen_addr "$a" || { echo -e "${RED}❌ 监听地址无效：${a}${PLAIN}"; return 1; }
    done
    for a in "${SITE_BACKEND_ADDRS[@]}"; do
        is_valid_backend_addr "$a" || { echo -e "${RED}❌ 后端地址无效：${a}${PLAIN}"; return 1; }
    done
    is_valid_path_prefix "$PANEL_WEB_PATH" || { echo -e "${RED}❌ 面板公网路径无效：${PANEL_WEB_PATH}${PLAIN}"; return 1; }
    is_valid_path_prefix "$SUB_URI_PATH" || { echo -e "${RED}❌ 普通订阅路径前缀无效：${SUB_URI_PATH}${PLAIN}"; return 1; }
    is_valid_path_prefix "$CLASH_URI_PATH" || { echo -e "${RED}❌ Clash/Mihomo 订阅路径前缀无效：${CLASH_URI_PATH}${PLAIN}"; return 1; }
    if [[ "$PANEL_WEB_PATH" == "$SUB_URI_PATH" || "$PANEL_WEB_PATH" == "$CLASH_URI_PATH" || "$SUB_URI_PATH" == "$CLASH_URI_PATH" ]]; then
        echo -e "${RED}❌ 面板路径、普通订阅路径、Clash/Mihomo 路径不能相同。${PLAIN}"
        return 1
    fi
    SITE_DOMAIN="${SITE_DOMAINS[0]:-}"
    SITE_BACKEND_ADDR="${SITE_BACKEND_ADDRS[0]:-127.0.0.1}"
    SITE_BACKEND_PORT="${SITE_BACKEND_PORTS[0]:-3000}"
    if [[ -n "${panel_whitelist_ranges:-}" ]]; then
        set_sni_ip_whitelist_for_domain "$PANEL_DOMAIN" "$panel_whitelist_ranges"
    fi
    [[ "$NGINX_LISTEN_PORT" != "443" ]] && echo -e "${YELLOW}⚠️  Nginx 公网端口不是 443，不推荐。${PLAIN}"

    warn_if_public_bind "Caddy" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    warn_if_public_bind "3x-ui 面板" "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT" || return 1
    warn_if_public_bind "3x-ui 订阅服务" "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT" || return 1

    if [[ -z "$CF_TOKEN" || ${#CF_TOKEN} -lt 20 ]]; then echo -e "${RED}❌ Cloudflare Token 长度异常。${PLAIN}"; return 1; fi
    echo -e "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}"
    verify_cf_token_online "$CF_TOKEN"
    local verify_rc=$?
    if [[ "$verify_rc" -eq 0 ]]; then
        echo -e "${GREEN}✅ Cloudflare Token 校验通过。${PLAIN}"
    elif [[ "$verify_rc" -eq 2 ]]; then
        echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}"
    else
        echo -e "${RED}❌ Cloudflare Token 校验失败。${PLAIN}"
        return 1
    fi
}
