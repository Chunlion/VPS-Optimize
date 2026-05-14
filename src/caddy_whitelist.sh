# shellcheck shell=bash
# Caddy/Web domain whitelist config block manipulation and menu flow.

strip_caddy_ip_whitelist_block() {
    local conf_file="$1"
    local tmp_file
    tmp_file=$(mktemp /tmp/caddy-ipwl.XXXXXX) || return 1
    awk '
        /# vps-optimize-ip-whitelist-start/ {skip=1; next}
        /# vps-optimize-ip-whitelist-end/ {skip=0; next}
        !skip {print}
    ' "$conf_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv "$tmp_file" "$conf_file"
}

insert_caddy_ip_whitelist_block() {
    local conf_file="$1"
    local ranges="$2"
    local tmp_file block
    strip_caddy_ip_whitelist_block "$conf_file" || return 1
    tmp_file=$(mktemp /tmp/caddy-ipwl.XXXXXX) || return 1
    block=$(caddy_ip_whitelist_block "$ranges")
    awk -v block="$block" '
        inserted == 0 && /^[[:space:]]*[^#[:space:]].*\{[[:space:]]*$/ {
            print
            printf "%s", block
            inserted=1
            next
        }
        {print}
        END { if (inserted == 0) exit 1 }
    ' "$conf_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv "$tmp_file" "$conf_file"
}

func_caddy_manage_ip_whitelist() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔐 普通 Caddy 域名 IP 白名单${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}适用于未启用 443 单入口、由 Caddy 直接对外服务的域名。${PLAIN}"
    echo -e "${YELLOW}如果该域名已接入 443 单入口，请用 [19] -> [9]，不要在 Caddy 层限制。${PLAIN}"
    echo -e "------------------------------------------------"

    if ! command -v caddy >/dev/null 2>&1 || [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e "${RED}❌ 未检测到 Caddy 或 /etc/caddy/Caddyfile，请先配置普通 Caddy 反代。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    local domain conf_file first_site_line action backup_file
    read_trimmed domain "请输入要管理的域名 (如 panel.example.com): "
    domain=$(normalize_domain_input "$domain")
    if ! is_valid_domain "$domain"; then
        echo -e "${RED}❌ 域名格式无效。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    conf_file="/etc/caddy/conf.d/${domain}.caddy"
    if [[ ! -f "$conf_file" ]]; then
        echo -e "${RED}❌ 未找到 ${conf_file}。该入口只管理脚本创建的模块化 Caddy 域名配置。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    first_site_line=$(grep -m1 -E '^[[:space:]]*[^#[:space:]].*\{' "$conf_file" 2>/dev/null | sed 's/^[[:space:]]*//')
    if [[ "$first_site_line" != "$domain "* && "$first_site_line" != "$domain{"* && "$first_site_line" != "https://${domain}"* ]]; then
        echo -e "${RED}❌ ${conf_file} 的首个站点块不是 ${domain}，为避免误改已取消。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    if [[ "$first_site_line" =~ ^https://[^[:space:]]+:[0-9]+[[:space:]]*\{ ]]; then
        echo -e "${RED}❌ 这个配置看起来属于 443 单入口本地 Caddy TLS 站点。请改用 [19] -> [9] 管理白名单。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    echo -e "当前配置文件：${conf_file}"
    if grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
        echo -e "${YELLOW}当前状态：已启用脚本管理的 IP 白名单。${PLAIN}"
    else
        echo -e "${BLUE}当前状态：未启用脚本管理的 IP 白名单。${PLAIN}"
    fi
    echo -e "1. 设置/覆盖白名单"
    echo -e "2. 清除白名单"
    echo -e "0. 取消"
    read_trimmed action "请选择操作: "

    backup_file="${conf_file}.bak_$(date +%s)"
    case "$action" in
        1)
            local ip_whitelist_input ip_whitelist_ranges current_client_ip
            local -a ip_whitelist_array=()
            current_client_ip=$(detect_ssh_client_ip)
            [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
            read_trimmed ip_whitelist_input "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
            if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
                echo -e "${RED}❌ 白名单为空或格式错误，已取消操作。${PLAIN}"
                read -n 1 -s -r -p "按任意键继续..."
                return
            fi
            append_vps_public_ips_to_whitelist ip_whitelist_array
            ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
            cp -p "$conf_file" "$backup_file" || { echo -e "${RED}❌ 备份失败，已取消。${PLAIN}"; read -n 1 -s -r -p "按任意键继续..."; return; }
            if insert_caddy_ip_whitelist_block "$conf_file" "$ip_whitelist_ranges" && caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                if systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}"
                    echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
                else
                    echo -e "${RED}❌ Caddy 重载失败，正在回滚...${PLAIN}"
                    mv "$backup_file" "$conf_file"
                    systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
                fi
            else
                echo -e "${RED}❌ 写入后 Caddy 校验失败，正在回滚...${PLAIN}"
                mv "$backup_file" "$conf_file"
            fi
            ;;
        2)
            if ! grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
                echo -e "${BLUE}该域名没有脚本管理的白名单块，无需清除。${PLAIN}"
                read -n 1 -s -r -p "按任意键继续..."
                return
            fi
            cp -p "$conf_file" "$backup_file" || { echo -e "${RED}❌ 备份失败，已取消。${PLAIN}"; read -n 1 -s -r -p "按任意键继续..."; return; }
            if strip_caddy_ip_whitelist_block "$conf_file" && caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
                echo -e "${GREEN}✅ 已清除 ${domain} 的 IP 白名单。${PLAIN}"
                echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
            else
                echo -e "${RED}❌ 清除后 Caddy 校验失败，正在回滚...${PLAIN}"
                mv "$backup_file" "$conf_file"
            fi
            ;;
        0|"")
            echo -e "${BLUE}已取消。${PLAIN}"
            ;;
        *)
            echo -e "${RED}❌ 无效操作。${PLAIN}"
            ;;
    esac

    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 优化重构：核弹级域名证书清理与解除端口占用 (模块化安全版)
# ---------------------------------------------------------
