# shellcheck shell=bash
# 443 single-entry web-domain and custom TCP-route CRUD workflows.

list_sni_stack_sites() {
    load_sni_stack_env || return 1
    local web_engine web_label
    web_engine=$(current_web_proxy_engine)
    web_label=$(web_proxy_engine_label "$web_engine")
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}当前 443 单入口网站/反代域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "Web 反代引擎：${web_label} (${web_engine}) -> $(web_proxy_backend)"
    echo -e "面板域名：${PANEL_DOMAIN} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    local panel_ranges
    panel_ranges=$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")
    [[ -n "$panel_ranges" ]] && echo -e "${YELLOW}面板域名 IP 白名单：${panel_ranges}${PLAIN}"
    echo -e "REALITY SNI：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]] && echo -e "${CYAN}另有 ${#TCP_ROUTE_SNIS[@]} 个旧 TCP/SNI 入站。${PLAIN}"
        [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]] && echo -e "${CYAN}另有 ${#XRAY_SNI_ROUTE_SNIS[@]} 个 Xray 入站，请在 [19] -> [15] 查看。${PLAIN}"
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
    local web_engine web_label
    web_engine=$(current_web_proxy_engine)
    web_label=$(web_proxy_engine_label "$web_engine")
    echo -e "${YELLOW}新增域名会走：公网 ${NGINX_LISTEN_PORT} -> 443 入口分流 -> ${web_label} -> 本地后端。${PLAIN}"
    echo -e ""

    local site_domain site_domain_input site_addr site_port advanced_mode existing idx confirm
    local enable_ip_whitelist whitelist_input whitelist_ranges current_client_ip
    local -a whitelist_array=()
    read_trimmed site_domain_input "请输入新网站/反代域名（例如 sub.example.com）: "
    site_domain=$(normalize_domain_input "$site_domain_input")
    if [[ -z "$site_domain" || "$site_domain" == "0" ]]; then
        echo -e "${BLUE}已取消新增网站/反代域名。${PLAIN}"
        return 0
    fi

    if ! is_valid_domain "$site_domain"; then
        print_domain_validation_error "域名" "$site_domain_input" "$site_domain"
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
    if is_yes "$advanced_mode"; then
        site_addr=$(ask_with_default "后端监听地址" "127.0.0.1")
    else
        site_addr="127.0.0.1"
        echo -e "${GREEN}普通模式：后端地址使用 127.0.0.1。${PLAIN}"
    fi
    site_port=$(ask_with_default "后端端口" "$((3000 + ${#SITE_DOMAINS[@]}))")

    is_valid_listen_addr "$site_addr" || { echo -e "${RED}❌ 后端监听地址无效：${site_addr}${PLAIN}"; return 1; }
    is_valid_port "$site_port" || { echo -e "${RED}❌ 后端端口无效：${site_port}${PLAIN}"; return 1; }
    warn_if_public_bind "网站/反代后端 ${site_domain}" "$site_addr" "$site_port" || return 1

    if web_proxy_engine_supports_web_whitelist "${ENTRY_MODE:-$(get_entry_mode)}" "$web_engine"; then
        read_trimmed enable_ip_whitelist "是否为 ${site_domain} 启用 IP 白名单？(y/n，默认 n): "
    else
        echo -e "${YELLOW}当前组合为 xray-fallback + Nginx 本地 Web 反代，无法可靠获取真实客户端源 IP，本次禁止为新域名启用 Web 白名单。${PLAIN}"
        echo -e "${YELLOW}如需 Web 白名单，请改用 Nginx Stream/TCP Peek 入口模式，或选择 Caddy 作为 Web 反代引擎。${PLAIN}"
        enable_ip_whitelist="n"
    fi
    if is_yes "$enable_ip_whitelist"; then
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
        "证书、Web 反代引擎配置和 443 入口分流配置" \
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
    echo -e "${CYAN}当前 Web 反代后端：${web_label} -> ${site_addr}:${site_port}${PLAIN}"
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
        "Web 反代引擎后端和 443 入口分流配置" \
        "使用 443 单入口备份恢复修改前配置" \
        "确认新后端地址和端口已经在本机监听。" || return 1

    SITE_BACKEND_ADDRS[$idx]="$new_addr"
    SITE_BACKEND_PORTS[$idx]="$new_port"
    apply_sni_stack_runtime_config || return 1
    echo -e "${GREEN}✅ 已更新网站后端：https://${domain}/ -> ${new_addr}:${new_port}${PLAIN}"
    echo -e "${CYAN}当前 Web 反代后端：$(web_proxy_engine_label) -> ${new_addr}:${new_port}${PLAIN}"
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
        "该域名的 Web 反代引擎配置和 443 入口分流规则" \
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
    if is_yes "$delete_cert"; then
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

switch_sni_stack_web_proxy_engine() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}切换 443 Web 反代引擎${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local current_engine current_label choice new_engine new_label entry_mode
    current_engine=$(current_web_proxy_engine)
    current_label=$(web_proxy_engine_label "$current_engine")
    entry_mode="${ENTRY_MODE:-$(get_entry_mode)}"

    echo -e "当前入口模式：${entry_mode}"
    echo -e "当前 Web 反代引擎：${current_label} (${current_engine})"
    echo -e "本地 TLS 后端：$(web_proxy_backend)"
    echo -e "读取来源：/etc/vps-optimize/sni-stack.env（脚本保存的 443 共享配置）"
    echo -e "${YELLOW}切换时会按当前域名、证书、后端和白名单重新渲染所选引擎，并隔离另一套 443 本地 Web 反代配置。${PLAIN}"
    echo -e "${YELLOW}如果你手工改过 Caddy/Nginx 文件但没有通过本菜单保存，请先在 [8]/[10] 同步脚本保存值后再切换。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${GREEN}  1. Caddy 本地 HTTPS 反代${PLAIN}"
    echo -e "${GREEN}  2. Nginx 本地 HTTPS 反代${PLAIN}"
    echo -e "${RED}  0. 取消${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    read_trimmed choice "请选择 Web 反代引擎（默认保持当前）: "
    case "$choice" in
        ""|0|q|Q)
            echo -e "${BLUE}已取消切换 Web 反代引擎。${PLAIN}"
            return 0
            ;;
        1) new_engine="caddy" ;;
        2) new_engine="nginx" ;;
        *)
            echo -e "${RED}❌ 无效的 Web 反代引擎选择。${PLAIN}"
            return 1
            ;;
    esac

    new_label=$(web_proxy_engine_label "$new_engine")
    if [[ "$new_engine" == "$current_engine" ]]; then
        echo -e "${BLUE}Web 反代引擎未变化，仍为 ${current_label}。${PLAIN}"
        return 0
    fi

    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -gt 0 ]] && ! web_proxy_engine_supports_web_whitelist "$entry_mode" "$new_engine"; then
        echo -e "${RED}❌ 不能切换到 ${new_label}：当前已有 Web 白名单，且 xray-fallback + Nginx 本地反代无法可靠获取真实客户端源 IP。${PLAIN}"
        echo -e "${YELLOW}请先清除 Web 白名单，或改用 Nginx Stream/TCP Peek 入口模式后再切换。${PLAIN}"
        return 1
    fi
    if ! web_proxy_engine_supports_web_whitelist "$entry_mode" "$new_engine"; then
        echo -e "${YELLOW}⚠️ 当前入口模式为 xray-fallback，切换到 Nginx 本地反代后将禁止新增 Web 白名单。${PLAIN}"
    fi

    confirm_risk_action "切换 443 Web 反代引擎为 ${new_label}" \
        "重新生成 ${new_label} 配置，并隔离旧的 443 本地 Web 反代配置；公网 443 入口模式保持 ${entry_mode}" \
        "使用 443 单入口备份恢复，或切回 ${current_label} 后重新应用" \
        "确认本机 ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} 未被其他服务占用，且证书文件仍在 /etc/caddy/certs/。" || return 1

    WEB_PROXY_ENGINE="$new_engine"
    save_and_offer_reapply_sni_stack
}

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

    local route_sni route_sni_input route_addr route_port existing idx
    read_trimmed route_sni_input "请输入用于分流的新 SNI/域名（例如 relay.example.com）: "
    route_sni=$(normalize_domain_input "$route_sni_input")
    if [[ -z "$route_sni" || "$route_sni" == "0" ]]; then
        echo -e "${BLUE}已取消新增 TCP/SNI 入站。${PLAIN}"
        return 0
    fi
    is_valid_domain "$route_sni" || { print_domain_validation_error "SNI/域名" "$route_sni_input" "$route_sni"; return 1; }
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
        echo -e "${RED}❌ 入站端口不能复用公网入口、Web 反代、面板或订阅服务端口。${PLAIN}"
        return 1
    fi

    echo -e ""
    echo -e "${CYAN}即将添加 TCP/SNI 分流：${route_sni}:${NGINX_LISTEN_PORT} -> ${route_addr}:${route_port}${PLAIN}"
    echo -e "${YELLOW}请确认 3x-ui 入站已监听 ${route_addr}:${route_port}，且客户端连接端口使用 ${NGINX_LISTEN_PORT}。${PLAIN}"
    echo -e "${YELLOW}说明：Web 白名单只保护 Web 域名，不会应用到 TCP/SNI 或 Xray 节点流量。${PLAIN}"
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

    local i num choice idx old_sni new_sni new_sni_input new_addr new_port existing
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
    new_sni_input=$(ask_with_default "SNI/域名" "$old_sni")
    new_sni=$(normalize_domain_input "$new_sni_input")
    new_addr=$(ask_with_default "本地监听地址（只允许本地）" "${TCP_ROUTE_ADDRS[$idx]}")
    new_addr=$(normalize_loopback_addr "$new_addr")
    new_port=$(ask_with_default "本地监听端口" "${TCP_ROUTE_PORTS[$idx]}")

    is_valid_domain "$new_sni" || { print_domain_validation_error "SNI/域名" "$new_sni_input" "$new_sni"; return 1; }
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
