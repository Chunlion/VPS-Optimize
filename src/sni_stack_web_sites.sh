# shellcheck shell=bash
# 443 stack web-domain CRUD workflows.

list_sni_stack_sites() {
    load_sni_stack_env || return 1
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}当前 443 单入口网站/反代域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "面板域名：${PANEL_DOMAIN} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    local panel_ranges
    panel_ranges=$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")
    [[ -n "$panel_ranges" ]] && echo -e "${YELLOW}面板域名 IP 白名单：${panel_ranges}${PLAIN}"
    echo -e "REALITY SNI：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]] && echo -e "${CYAN}另有 ${#TCP_ROUTE_SNIS[@]} 个旧 TCP/SNI 入站。${PLAIN}"
        [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]] && echo -e "${CYAN}另有 ${#XRAY_SNI_ROUTE_SNIS[@]} 个 Xray 入站，请在 [19] -> [10] 查看。${PLAIN}"
    echo -e "------------------------------------------------"
    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有额外的网站/反代域名。${PLAIN}"
        return 0
    fi

    local i num
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} https://${SITE_DOMAINS[$i]}/ -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
        local site_ranges
        site_ranges=$(sni_ip_whitelist_ranges_for_domain "${SITE_DOMAINS[$i]}")
        [[ -n "$site_ranges" ]] && echo -e "   ${YELLOW}IP 白名单：${site_ranges}${PLAIN}"
    done
}

add_sni_stack_site() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}添加 443 网站/反代域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    if [[ ! -f "$cf_env_file" ]]; then
        echo -e "${RED}❌ 未找到 Cloudflare Token，请先进入维护菜单 [2] 写入 Token。${PLAIN}"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$cf_env_file"
    if [[ -z "${CF_Token:-}" ]]; then
        echo -e "${RED}❌ Cloudflare Token 为空，请先进入维护菜单 [2] 更新。${PLAIN}"
        return 1
    fi

    echo -e "这个入口适合后续新增网站，例如 SublinkPro、Dockge、博客、订阅管理工具等。"
    echo -e "${YELLOW}新增域名会走：公网 ${NGINX_LISTEN_PORT} -> Nginx SNI -> Caddy -> 本地后端。${PLAIN}"
    echo -e ""

    local site_domain site_addr site_port advanced_mode existing idx confirm
    local enable_ip_whitelist whitelist_input whitelist_ranges current_client_ip
    local -a whitelist_array=()
    read_trimmed site_domain "请输入新网站/反代域名（例如 sub.example.com）: "
    site_domain=$(normalize_domain_input "$site_domain")
    if [[ -z "$site_domain" || "$site_domain" == "0" ]]; then
        echo -e "${BLUE}已取消新增网站/反代域名。${PLAIN}"
        return 0
    fi

    if ! is_valid_domain "$site_domain"; then
        echo -e "${RED}❌ 域名格式无效。${PLAIN}"
        return 1
    fi
    if [[ "$site_domain" == "$PANEL_DOMAIN" || "$site_domain" == "$REALITY_SNI" ]]; then
        echo -e "${RED}❌ 新域名不能和面板域名或 REALITY SNI 相同。${PLAIN}"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        if [[ "$site_domain" == "$existing" ]]; then
            echo -e "${RED}❌ 该域名已经在 443 分流列表中。${PLAIN}"
            return 1
        fi
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        if [[ "$site_domain" == "$existing" ]]; then
            echo -e "${RED}❌ 该域名已经作为 TCP/SNI 入站使用。${PLAIN}"
            return 1
        fi
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        if [[ "$site_domain" == "$existing" ]]; then
            echo -e "${RED}❌ 该域名已经作为 Xray 入站使用。${PLAIN}"
            return 1
        fi
    done

    read_trimmed advanced_mode "是否进入高级模式并允许修改后端监听地址？(y/n，默认 n): "
    if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
        site_addr=$(ask_with_default "后端监听地址" "127.0.0.1")
    else
        site_addr="127.0.0.1"
        echo -e "${GREEN}普通模式：后端地址使用 127.0.0.1。${PLAIN}"
    fi
    site_port=$(ask_with_default "后端端口" "$((3000 + ${#SITE_DOMAINS[@]}))")

    is_valid_listen_addr "$site_addr" || { echo -e "${RED}❌ 后端监听地址无效：${site_addr}${PLAIN}"; return 1; }
    is_valid_port "$site_port" || { echo -e "${RED}❌ 后端端口无效：${site_port}${PLAIN}"; return 1; }
    warn_if_public_bind "网站/反代后端 ${site_domain}" "$site_addr" "$site_port" || return 1

    read_trimmed enable_ip_whitelist "是否为 ${site_domain} 启用 IP 白名单？(y/n，默认 n): "
    if [[ "$enable_ip_whitelist" =~ ^[Yy]$ ]]; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
        read_trimmed whitelist_input "请输入允许访问 ${site_domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
        normalize_ip_whitelist_input "$whitelist_input" whitelist_array || return 1
        append_vps_public_ips_to_whitelist whitelist_array
        whitelist_ranges=$(join_array_by_space "${whitelist_array[@]}")
    fi

    echo -e ""
    echo -e "${CYAN}即将添加：${site_domain} -> ${site_addr}:${site_port}${PLAIN}"
    [[ -n "${whitelist_ranges:-}" ]] && echo -e "${YELLOW}IP 白名单：${whitelist_ranges}${PLAIN}"
    confirm_risk_action "新增 443 网站/反代域名 ${site_domain}" \
        "证书、Caddy 站点配置和 Nginx SNI 分流配置" \
        "使用 443 单入口备份恢复，或从网站管理菜单删除该域名" \
        "确认域名已解析到当前 VPS，后端端口可从本机访问。" || return 1

    idx=${#SITE_DOMAINS[@]}
    SITE_DOMAINS[$idx]="$site_domain"
    SITE_BACKEND_ADDRS[$idx]="$site_addr"
    SITE_BACKEND_PORTS[$idx]="$site_port"
    [[ -n "${whitelist_ranges:-}" ]] && set_sni_ip_whitelist_for_domain "$site_domain" "$whitelist_ranges"

    issue_and_install_cert_for_domain "$site_domain" "$CF_Token" || return 1
    apply_sni_stack_runtime_config || return 1
    echo -e "${GREEN}✅ 已添加网站入口：https://${site_domain}/${PLAIN}"
    echo -e "${YELLOW}提醒：后端服务需要监听 ${site_addr}:${site_port}，浏览器只访问 https://${site_domain}/。${PLAIN}"
    echo -e "${CYAN}当前 Caddy 后端：reverse_proxy ${site_addr}:${site_port}${PLAIN}"
}

edit_sni_stack_site_backend() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改 443 网站/反代后端${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可修改的网站/反代域名。${PLAIN}"
        return 0
    fi

    local i num choice idx domain new_addr new_port confirm
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${SITE_DOMAINS[$i]} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "请输入要修改的序号: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消修改。${PLAIN}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#SITE_DOMAINS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    domain="${SITE_DOMAINS[$idx]}"
    new_addr=$(ask_with_default "后端监听地址" "${SITE_BACKEND_ADDRS[$idx]}")
    new_port=$(ask_with_default "后端端口" "${SITE_BACKEND_PORTS[$idx]}")

    is_valid_listen_addr "$new_addr" || { echo -e "${RED}❌ 后端监听地址无效：${new_addr}${PLAIN}"; return 1; }
    is_valid_port "$new_port" || { echo -e "${RED}❌ 后端端口无效：${new_port}${PLAIN}"; return 1; }
    warn_if_public_bind "网站/反代后端 ${domain}" "$new_addr" "$new_port" || return 1

    echo -e ""
    echo -e "${CYAN}即将修改：${domain} -> ${new_addr}:${new_port}${PLAIN}"
    confirm_risk_action "修改 443 网站/反代后端" \
        "Caddy 反代后端和 Nginx SNI 分流配置" \
        "使用 443 单入口备份恢复修改前配置" \
        "确认新后端地址和端口已经在本机监听。" || return 1

    SITE_BACKEND_ADDRS[$idx]="$new_addr"
    SITE_BACKEND_PORTS[$idx]="$new_port"
    apply_sni_stack_runtime_config || return 1
    echo -e "${GREEN}✅ 已更新网站后端：https://${domain}/ -> ${new_addr}:${new_port}${PLAIN}"
    echo -e "${CYAN}当前 Caddy 后端：reverse_proxy ${new_addr}:${new_port}${PLAIN}"
}

remove_sni_stack_site() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}删除 443 网站/反代域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可删除的网站/反代域名。${PLAIN}"
        return 0
    fi

    local i num choice idx domain confirm delete_cert new_domains new_addrs new_ports
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${SITE_DOMAINS[$i]} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "请输入要删除的序号: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消删除。${PLAIN}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#SITE_DOMAINS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    domain="${SITE_DOMAINS[$idx]}"
    confirm_risk_action "从 443 分流中移除 ${domain}" \
        "该域名的 Caddy 站点和 Nginx SNI 分流规则" \
        "使用 443 单入口备份恢复，或重新新增该网站/反代域名" \
        "确认该域名不再承载线上面板、订阅或网站。" || return 1

    new_domains=()
    new_addrs=()
    new_ports=()
    for i in "${!SITE_DOMAINS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_domains+=("${SITE_DOMAINS[$i]}")
        new_addrs+=("${SITE_BACKEND_ADDRS[$i]}")
        new_ports+=("${SITE_BACKEND_PORTS[$i]}")
    done
    SITE_DOMAINS=("${new_domains[@]}")
    SITE_BACKEND_ADDRS=("${new_addrs[@]}")
    SITE_BACKEND_PORTS=("${new_ports[@]}")
    remove_sni_ip_whitelist_for_domain "$domain"
    quarantine_path "/etc/caddy/conf.d/${domain}.caddy" "/etc/vps-optimize/quarantine/caddy-sni" >/dev/null 2>&1 || true

    apply_sni_stack_runtime_config || return 1

    read_trimmed delete_cert "是否同时隔离 ${domain} 的 Caddy 证书文件？(y/n，默认 n): "
    if [[ "$delete_cert" =~ ^[Yy]$ ]]; then
        quarantine_path "/etc/caddy/certs/${domain}.crt" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        quarantine_path "/etc/caddy/certs/${domain}.key" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        quarantine_path "/root/cert/${domain}.crt" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        quarantine_path "/root/cert/${domain}.key" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        generate_caddy_cf_manifest
        echo -e "${GREEN}✅ 已移除 ${domain} 的配置，并隔离本地证书文件。${PLAIN}"
    else
        echo -e "${GREEN}✅ 已删除 ${domain} 的分流配置，证书文件已保留。${PLAIN}"
    fi
}
