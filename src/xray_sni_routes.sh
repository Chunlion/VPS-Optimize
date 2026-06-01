# shellcheck shell=bash
# Xray SNI route records and sync workflows for nginx-stream/tcp-peek modes.

xray_sni_routes_fallback_notice() {
    echo -e "${YELLOW}当前为 Xray Fallback 模式。${PLAIN}"
    print_xray_fallback_mode_explanation
}

list_xray_sni_routes() {
    load_sni_stack_env || return 1
    local mode fallback_idx
    mode=$(get_entry_mode)
    fallback_idx=$(xray_fallback_main_route_index 2>/dev/null || true)
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}Xray 入站分流规则${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "配置文件：$(xray_sni_routes_path)"
    echo -e "规则格式：SNI|ADDR|PORT"
    if [[ "$mode" == "xray-fallback" ]]; then
        echo -e "------------------------------------------------"
        xray_sni_routes_fallback_notice
        print_xray_fallback_main_route_summary
    fi
    echo -e "------------------------------------------------"
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有 Xray 入站分流规则。${PLAIN}"
        if [[ -n "${XRAY_LISTEN_PORT:-}" ]]; then
            echo -e "${CYAN}旧默认 Xray/REALITY 后端仍是：${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}${PLAIN}"
            echo -e "${CYAN}如需多个本地 Xray 入站，可按 SNI 添加新的本地端口分流记录。${PLAIN}"
        fi
        return 0
    fi

    local i num
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        if [[ "$mode" == "xray-fallback" && -n "$fallback_idx" && "$i" == "$fallback_idx" ]]; then
            echo -e "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]} ${GREEN}[xray-fallback 主入站，当前模式生效]${PLAIN}"
        elif [[ "$mode" == "xray-fallback" ]]; then
            echo -e "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]} ${YELLOW}[已保留，当前 xray-fallback 模式下不生效]${PLAIN}"
        else
            echo -e "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]}"
        fi
    done
}

add_xray_sni_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}添加 Xray 入站分流规则${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}本菜单只记录 SNI -> 本地地址:端口；用于当前支持的单入口模式渲染分流规则，不会创建、删除或修改 3x-ui/Xray 入站内部配置。${PLAIN}"
    echo -e "------------------------------------------------"

    local route_sni route_sni_input route_addr route_port existing idx
    read_trimmed route_sni_input "SNI/域名: "
    route_sni=$(normalize_domain_input "$route_sni_input")
    if [[ -z "$route_sni" || "$route_sni" == "0" ]]; then
        echo -e "${BLUE}已取消添加。${PLAIN}"
        return 0
    fi
    is_valid_domain "$route_sni" || { print_domain_validation_error "SNI/域名" "$route_sni_input" "$route_sni"; return 1; }
    if [[ "$route_sni" == "$PANEL_DOMAIN" || "$route_sni" == "$REALITY_SNI" ]]; then
        echo -e "${RED}❌ Xray 入站域名不能和面板域名或 REALITY SNI 相同。${PLAIN}"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已作为 Web 域名使用，Xray 入站规则必须和 Web 域名分开。${PLAIN}"; return 1; }
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已存在于旧 TCP/SNI 本地入站规则中。${PLAIN}"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该 Xray 入站分流规则已经存在。${PLAIN}"; return 1; }
    done

    route_addr=$(ask_with_default "本地监听地址" "127.0.0.1")
    route_addr=$(normalize_loopback_addr "$route_addr")
    route_port=$(ask_with_default "本地监听端口" "${XRAY_LISTEN_PORT:-1443}")
    is_loopback_listen_addr "$route_addr" || { echo -e "${RED}❌ 为避免公网暴露，本地监听地址只允许 127.0.0.1、localhost 或 ::1。${PLAIN}"; return 1; }
    is_valid_port "$route_port" || { echo -e "${RED}❌ 本地监听端口无效：${route_port}${PLAIN}"; return 1; }
    if [[ "$route_port" == "$CADDY_LISTEN_PORT" ]]; then
        echo -e "${RED}❌ 该端口与 Web 反代引擎本地端口 ${CADDY_LISTEN_PORT} 冲突。${PLAIN}"
        return 1
    fi
    if [[ "$route_port" == "$NGINX_LISTEN_PORT" || "$route_port" == "$PANEL_LISTEN_PORT" || "$route_port" == "$SUB_LISTEN_PORT" ]]; then
        echo -e "${RED}❌ 入站端口不能复用公网入口、面板或订阅服务端口。${PLAIN}"
        return 1
    fi
    existing=$(xray_sni_route_port_conflict "$route_addr" "$route_port" || true)
    if [[ -n "$existing" ]]; then
        echo -e "${RED}❌ ${route_addr}:${route_port} 已被规则 ${existing} 使用。${PLAIN}"
        return 1
    fi

    print_xray_route_port_status "$route_sni" "$route_addr" "$route_port"
    if [[ -z "$(xray_route_listen_line_by_addr_port "$route_addr" "$route_port")" ]]; then
        echo -e "${RED}❌ 端口未监听，请先去 3x-ui 创建并启用对应入站。${PLAIN}"
        return 1
    fi

    idx=${#XRAY_SNI_ROUTE_SNIS[@]}
    XRAY_SNI_ROUTE_SNIS[$idx]="$route_sni"
    XRAY_SNI_ROUTE_ADDRS[$idx]="$route_addr"
    XRAY_SNI_ROUTE_PORTS[$idx]="$route_port"
    save_xray_sni_route_arrays
    echo -e "${GREEN}✅ 已保存 Xray 入站分流规则：${route_sni} -> ${route_addr}:${route_port}${PLAIN}"
    echo -e "${YELLOW}提示：保存后需要执行“同步到当前入口模式”或重新应用当前入口模式，公网 443 才会使用新规则。${PLAIN}"
}

remove_xray_sni_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}删除 Xray 入站分流规则${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可删除的 Xray 入站分流规则。${PLAIN}"
        return 0
    fi

    local i num choice idx route_sni
    local -a new_snis=() new_addrs=() new_ports=()
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "请输入要删除的序号: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消删除。${PLAIN}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#XRAY_SNI_ROUTE_SNIS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    route_sni="${XRAY_SNI_ROUTE_SNIS[$idx]}"
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_snis+=("${XRAY_SNI_ROUTE_SNIS[$i]}")
        new_addrs+=("${XRAY_SNI_ROUTE_ADDRS[$i]}")
        new_ports+=("${XRAY_SNI_ROUTE_PORTS[$i]}")
    done
    XRAY_SNI_ROUTE_SNIS=("${new_snis[@]}")
    XRAY_SNI_ROUTE_ADDRS=("${new_addrs[@]}")
    XRAY_SNI_ROUTE_PORTS=("${new_ports[@]}")
    save_xray_sni_route_arrays
    echo -e "${GREEN}✅ 已删除 Xray 入站分流规则：${route_sni}${PLAIN}"
    echo -e "${YELLOW}提示：删除后需要执行“同步到当前入口模式”或重新应用当前入口模式。${PLAIN}"
}

check_xray_sni_route_ports() {
    load_sni_stack_env || return 1
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}检查 Xray 入站端口状态${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有 Xray 入站分流规则。${PLAIN}"
        return 0
    fi

    local i
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        print_xray_route_port_status "${XRAY_SNI_ROUTE_SNIS[$i]}" "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}"
        echo -e "------------------------------------------------"
    done
}

sync_xray_sni_routes_to_entry_mode() {
    load_sni_stack_env || return 1
    local mode
    mode=$(get_entry_mode)
    case "$mode" in
        "nginx-stream")
            echo -e "${CYAN}正在同步 Xray 入站分流规则到 Nginx Stream 配置...${PLAIN}"
            reapply_sni_stack_from_env --yes
            ;;
        "tcp-peek")
            local tmp_config target_config
            echo -e "${CYAN}正在同步 Xray 入站分流规则到 TCP Peek + Splice 配置...${PLAIN}"
            target_config=$(vpso_mux_config_path)
            tmp_config="${target_config}.tmp.$$"
            write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$tmp_config" || return 1
            if ! run_vpso_mux_config_check "$tmp_config"; then
                quarantine_path "$tmp_config" "/etc/vps-optimize/quarantine/vpso-mux" >/dev/null 2>&1 || true
                return 1
            fi
            mv "$tmp_config" "$target_config" || { echo -e "${RED}❌ TCP Peek + Splice 配置替换失败：${target_config}${PLAIN}"; return 1; }
            if systemctl is-active --quiet vpso-mux 2>/dev/null; then
                systemctl restart vpso-mux || { print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"; echo -e "${RED}❌ vpso-mux 重启失败，请查看上面的日志。${PLAIN}"; return 1; }
            else
                echo -e "${YELLOW}vpso-mux 分流器当前未运行，已仅生成并校验配置文件。${PLAIN}"
            fi
            echo -e "${GREEN}✅ 已同步到 TCP Peek + Splice 配置：${target_config}${PLAIN}"
            ;;
        "xray-fallback")
            xray_sni_routes_fallback_notice
            return 1
            ;;
        *)
            echo -e "${RED}❌ 当前 ENTRY_MODE 无效或未配置：${mode}${PLAIN}"
            return 1
            ;;
    esac
}

manage_xray_inbound_routes() {
    load_sni_stack_env || return 1
    if [[ "$(get_entry_mode)" == "xray-fallback" ]]; then
        while true; do
            clear
            echo -e "${CYAN}================================================${PLAIN}"
            echo -e "${BOLD}Xray 入站管理${PLAIN}"
            echo -e "${CYAN}================================================${PLAIN}"
            xray_sni_routes_fallback_notice
            print_xray_fallback_main_route_summary
            echo -e "------------------------------------------------"
            echo -e "${GREEN}  1. 查看入站分流规则${PLAIN}"
            echo -e "${YELLOW}  2. 添加入站分流规则（当前模式不可用）${PLAIN}"
            echo -e "${YELLOW}  3. 删除入站分流规则（当前模式不可用）${PLAIN}"
            echo -e "${YELLOW}  4. 同步规则到当前入口模式（当前模式不可用）${PLAIN}"
            echo -e "------------------------------------------------"
            echo -e "${RED}  0. 返回 / q 返回${PLAIN}"
            echo -e "${CYAN}================================================${PLAIN}"

            local fallback_choice
            read_trimmed fallback_choice "请选择操作: "
            case "$fallback_choice" in
                1) list_xray_sni_routes ;;
                2|3|4)
                    echo -e "${YELLOW}当前为 xray-fallback 模式，Xray 入站管理默认不可新增、删除或同步规则。${PLAIN}"
                    echo -e "${YELLOW}如需多个本地 Xray 入站通过 443 按 SNI 分流，请切换到 nginx-stream 或 tcp-peek。${PLAIN}"
                    ;;
                0|q|Q) break ;;
                *) echo -e "${RED}❌ 无效选择。${PLAIN}" ;;
            esac
            echo ""
            read -n 1 -s -r -p "按任意键继续..."
        done
        return 0
    fi

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}Xray 入站管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}只管理 SNI -> 本地地址:端口 分流记录，用于当前支持的单入口模式渲染分流规则；不编辑 3x-ui/Xray 入站内部配置。${PLAIN}"
        echo -e "配置文件：$(xray_sni_routes_path)"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看入站分流规则${PLAIN}"
        echo -e "${GREEN}  2. 添加入站分流规则${PLAIN}"
        echo -e "${GREEN}  3. 删除入站分流规则${PLAIN}"
        echo -e "${GREEN}  4. 检查入站端口状态${PLAIN}"
        echo -e "${GREEN}  5. 同步到当前入口模式${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "请选择操作: "
        case "$choice" in
            1) list_xray_sni_routes ;;
            2) add_xray_sni_route ;;
            3) remove_xray_sni_route ;;
            4) check_xray_sni_route_ports ;;
            5) sync_xray_sni_routes_to_entry_mode ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择。${PLAIN}" ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

manage_sni_stack_tcp_routes() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}Xray 入站管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：记录你已在 3x-ui/Xray 配好的本地入站：SNI -> 本地地址:端口。${PLAIN}"
        echo -e "${YELLOW}这些记录用于当前支持的单入口模式渲染分流规则；脚本不开放新端口，不改 3x-ui/Xray 入站内部配置。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看当前 TCP/SNI 入站${PLAIN}"
        echo -e "${GREEN}  2. 新增 TCP/SNI 入站${PLAIN}"
        echo -e "${GREEN}  3. 修改 TCP/SNI 入站${PLAIN}"
        echo -e "${GREEN}  4. 删除 TCP/SNI 入站${PLAIN}"
        echo -e "${BLUE}  5. 查看 Web 白名单适用范围${PLAIN}"
        echo -e "${GREEN}  6. 重新应用并重启 Nginx/Caddy${PLAIN}"
        echo -e "${GREEN}  7. 443 单入口链路体检${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1) list_sni_stack_tcp_routes ;;
            2) add_sni_stack_tcp_route ;;
            3) edit_sni_stack_tcp_route ;;
            4) remove_sni_stack_tcp_route ;;
            5)
                echo -e "${YELLOW}Web 白名单只适用于 Web 域名：面板、订阅、普通网站、面板域名和自定义反代域名。${PLAIN}"
                echo -e "${YELLOW}TCP/SNI 入站和 Xray 节点流量不会启用 IP 白名单；如需限制来源，请在后端服务或防火墙侧单独设计。${PLAIN}"
                ;;
            6) reapply_sni_stack_from_env ;;
            7) sni_stack_health_check ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

manage_sni_stack_ip_whitelist() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🔐 443 域名 IP 白名单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        load_sni_stack_env || return 1
        local whitelist_supported="yes"
        if ! web_proxy_engine_supports_web_whitelist "${ENTRY_MODE:-$(get_entry_mode)}" "${WEB_PROXY_ENGINE:-caddy}"; then
            whitelist_supported="no"
        fi
        echo -e "${YELLOW}只限制你选择的 Web 域名；支持面板、订阅、网站/反代，Xray 入站、REALITY SNI 与未知 SNI 不受 Web 白名单影响。${PLAIN}"
        echo -e "${YELLOW}Nginx Stream/TCP Peek 入口会在入口层按 SNI + 源 IP 拦截，避免影响同入口其他服务。${PLAIN}"
        if [[ "$whitelist_supported" != "yes" ]]; then
            echo -e "${RED}当前组合为 xray-fallback + Nginx 本地 Web 反代，无法可靠获取真实客户端源 IP，禁止新增或覆盖 Web 白名单。${PLAIN}"
            echo -e "${YELLOW}你仍可清除已有白名单；如需继续使用白名单，请切到 Nginx Stream/TCP Peek，或选择 Caddy 作为 Web 反代引擎。${PLAIN}"
        fi
        echo -e "------------------------------------------------"

        local -a domains=("$PANEL_DOMAIN")
        local -a labels=("面板/订阅")
        local site_domain i num domain current_ranges
        for site_domain in "${SITE_DOMAINS[@]}"; do
            [[ -z "$site_domain" ]] && continue
            domains+=("$site_domain")
            labels+=("网站/反代")
        done
        for i in "${!domains[@]}"; do
            num=$((i + 1))
            current_ranges=$(sni_ip_whitelist_ranges_for_domain "${domains[$i]}")
            if [[ -n "$current_ranges" ]]; then
                echo -e "${GREEN}${num}.${PLAIN} [${labels[$i]}] ${domains[$i]}  ${YELLOW}仅允许：${current_ranges}${PLAIN}"
            else
                echo -e "${GREEN}${num}.${PLAIN} [${labels[$i]}] ${domains[$i]}  ${BLUE}未启用${PLAIN}"
            fi
        done
        echo -e "------------------------------------------------"
        echo -e "${RED}0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice idx action whitelist_input whitelist_ranges current_client_ip
        local -a whitelist_array=()
        read_trimmed choice "请输入要管理的域名序号: "
        [[ "$choice" == "0" || -z "$choice" ]] && break
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#domains[@]} )); then
            echo -e "${RED}❌ 序号无效。${PLAIN}"
            pause_return
            continue
        fi

        idx=$((choice - 1))
        domain="${domains[$idx]}"
        current_ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        echo -e "当前域名：${domain}"
        echo -e "当前白名单：${current_ranges:-未启用}"
        echo -e "1. 设置/覆盖白名单"
        echo -e "2. 清除白名单"
        echo -e "0/q. 取消"
        read_trimmed action "请选择操作: "
        case "$action" in
            1)
                if [[ "$whitelist_supported" != "yes" ]]; then
                    echo -e "${RED}❌ 当前组合禁止设置 Web 白名单。请先切换入口模式或 Web 反代引擎。${PLAIN}"
                    pause_return
                    continue
                fi
                current_client_ip=$(detect_ssh_client_ip)
                [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
                read_trimmed whitelist_input "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
                if ! normalize_ip_whitelist_input "$whitelist_input" whitelist_array; then
                    echo -e "${RED}❌ 白名单为空或格式错误，已取消。${PLAIN}"
                    pause_return
                    continue
                fi
                append_vps_public_ips_to_whitelist whitelist_array
                whitelist_ranges=$(join_array_by_space "${whitelist_array[@]}")
                confirm_risk_action "为 ${domain} 启用 IP 白名单" \
                    "443 入口层会仅对该 SNI 做源 IP 限制" \
                    "使用 443 单入口自动备份回滚，或清除该域名白名单后重新应用" \
                    "确认你的管理 IP 已包含在白名单中，且该域名不是 Cloudflare 橙云代理访问。" || continue
                set_sni_ip_whitelist_for_domain "$domain" "$whitelist_ranges"
                save_and_offer_reapply_sni_stack
                ;;
            2)
                if [[ -z "$current_ranges" ]]; then
                    echo -e "${BLUE}该域名未启用白名单。${PLAIN}"
                    pause_return
                    continue
                fi
                confirm_risk_action "清除 ${domain} 的 IP 白名单" \
                    "该域名会恢复为普通 443 分流访问" \
                    "重新设置该域名白名单" \
                    "确认这是你想要的公网访问策略。" || continue
                remove_sni_ip_whitelist_for_domain "$domain"
                save_and_offer_reapply_sni_stack
                ;;
            0|q|Q|"")
                ;;
            *)
                echo -e "${RED}❌ 无效操作。${PLAIN}"
                pause_return
                ;;
        esac
    done
}
