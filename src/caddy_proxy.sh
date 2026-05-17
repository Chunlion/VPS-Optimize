# shellcheck shell=bash
# Ordinary Caddy reverse proxy workflows outside the 443 single-entry stack.

func_caddy_add_reverse_proxy() {
    echo -e "${CYAN}▶ 正在检查并安装 Caddy...${PLAIN}"
    if ! install_caddy_if_needed; then
        echo -e "${RED}❌ Caddy 安装失败，请检查软件源、网络或系统版本。${PLAIN}"
        return 1
    fi
    if ! ensure_caddy_module_layout; then
        echo -e "${RED}❌ Caddy 配置目录初始化失败，请检查 /etc/caddy 权限。${PLAIN}"
        return 1
    fi

    local domain port is_https
    read_trimmed domain "请输入解析后的域名 (如 panel.site.com): "
    read_trimmed port "请输入面板本地映射端口 (如 40000): "
    domain=$(normalize_domain_input "$domain")

    if ! is_valid_domain "$domain" || ! is_valid_port "$port"; then
        echo -e "${RED}❌ 域名或端口格式错误！域名不要带 http(s)://、路径或端口，端口必须是 1-65535。${PLAIN}"
        return 1
    fi

    local domain_conf="/etc/caddy/conf.d/${domain}.caddy"
    if grep -q "^[[:space:]]*$domain" /etc/caddy/Caddyfile 2>/dev/null || [[ -e "$domain_conf" ]]; then
        echo -e "${RED}❌ 错误：已存在该域名的配置块！请先清理或更换域名后再添加。${PLAIN}"
        return 1
    fi

    read_trimmed is_https "❓ 后端面板是否开启了自带的 SSL 证书？(y/n): "

    local enable_ip_whitelist ip_whitelist_input ip_whitelist_ranges current_client_ip
    local -a ip_whitelist_array=()
    read_trimmed enable_ip_whitelist "❓ 是否只允许指定 IP/CIDR 访问该域名？(y/n，默认 n): "
    if is_yes "$enable_ip_whitelist"; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单，避免把自己挡在外面。${PLAIN}"
        read_trimmed ip_whitelist_input "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
        if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
            echo -e "${RED}❌ 白名单为空或格式错误，已取消本次反代配置。${PLAIN}"
            return 1
        fi
        append_vps_public_ips_to_whitelist ip_whitelist_array
        ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
    else
        ip_whitelist_ranges=""
    fi

    local backup_file="/etc/caddy/Caddyfile.bak_$(date +%s)"
    [[ -f /etc/caddy/Caddyfile ]] && cp -p /etc/caddy/Caddyfile "$backup_file"

    if is_yes "$is_https"; then
        cat <<EOF > "$domain_conf"
$domain {
$(caddy_ip_whitelist_block "$ip_whitelist_ranges")    reverse_proxy https://127.0.0.1:$port {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF
    else
        cat <<EOF > "$domain_conf"
$domain {
$(caddy_ip_whitelist_block "$ip_whitelist_ranges")    reverse_proxy localhost:$port
}
EOF
    fi

    echo -e "${CYAN}▶ 正在校验 Caddy 配置文件...${PLAIN}"
    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        if systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Caddy 反代配置已追加并生效！请访问 https://$domain${PLAIN}"
            [[ -n "$ip_whitelist_ranges" ]] && echo -e "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}"
            echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
        else
            echo -e "${RED}❌ Caddy 配置校验通过，但服务重载失败，正在回滚...${PLAIN}"
            [[ -f "$backup_file" ]] && mv "$backup_file" /etc/caddy/Caddyfile
            quarantine_path "$domain_conf" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
            systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
            return 1
        fi
    else
        echo -e "${RED}❌ 致命错误：生成的配置存在语法异常！正在自动回滚...${PLAIN}"
        [[ -f "$backup_file" ]] && mv "$backup_file" /etc/caddy/Caddyfile
        quarantine_path "$domain_conf" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
        return 1
    fi
}

func_caddy_reverse_proxy_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "普通 Caddy 反代"
        echo -e "${BOLD}🌐 普通 Caddy 反代${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：管理未接入 443 单入口的普通 Caddy 域名反代。443 单入口请只走主菜单 [19]。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 添加普通 Caddy 反代${PLAIN}"
        echo -e "${CYAN}  2. 查看 Caddy 证书路径${PLAIN}"
        echo -e "${CYAN}  3. Caddy 跳过后端证书校验${PLAIN} ${YELLOW}(后端自签 HTTPS 时使用)${PLAIN}"
        echo -e "${CYAN}  4. 普通 Caddy 域名 IP 白名单${PLAIN}"
        echo -e "${RED}  5. 清空 Caddy 配置${PLAIN}"
        echo -e "${RED}  6. 删除底层 ACME 证书${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local caddy_choice
        read_trimmed caddy_choice "👉 请选择操作: "
        case "$caddy_choice" in
            1) func_caddy_add_reverse_proxy ;;
            2) func_view_caddy_cert ;;
            3) func_caddy_add_insecure ;;
            4) func_caddy_manage_ip_whitelist ;;
            5) func_caddy_clear_config ;;
            6) func_caddy_delete_cert ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
        echo ""
        pause_return "按任意键继续..."
    done
}
