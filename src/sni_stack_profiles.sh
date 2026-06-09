# shellcheck shell=bash
# 443 single-entry profile editing and reapply helpers.

save_and_offer_reapply_sni_stack() {
    local yn env_file env_backup
    env_file="/etc/vps-optimize/sni-stack.env"
    env_backup=""
    if [[ -f "$env_file" ]]; then
        env_backup="${env_file}.pre_reapply_$(date +%Y%m%d_%H%M%S)"
        cp -p "$env_file" "$env_backup" 2>/dev/null || env_backup=""
    fi
    save_sni_stack_env
    echo -e "${GREEN}✅ 已保存新的 443 单入口运行参数。${PLAIN}"
    echo -e "${YELLOW}提示：保存后需要重新应用，Nginx/Caddy 才会使用新的域名、端口或路径。${PLAIN}"
    read_trimmed yn "是否现在重新应用并重启 Nginx/Caddy？输入 yes 继续，直接回车取消（大小写均可）: "
    if is_yes "$yn"; then
        if ! reapply_sni_stack_from_env --yes; then
            if [[ -n "$env_backup" && -f "$env_backup" ]]; then
                cp -p "$env_backup" "$env_file" 2>/dev/null || true
                echo -e "${YELLOW}⚠️ 已恢复重新应用前的参数文件：${env_backup}${PLAIN}"
            fi
            return 1
        fi
    else
        echo -e "${YELLOW}稍后可执行 [19] -> [6] 重新应用上次配置。${PLAIN}"
        [[ -n "$env_backup" ]] && echo -e "${CYAN}参数修改前备份已保留：${env_backup}${PLAIN}"
    fi
}

restart_xui_panel_services_after_setting_update() {
    local service_name restarted=0
    for service_name in x-ui 3x-ui x-panel; do
        if systemctl list-unit-files "${service_name}.service" --no-legend 2>/dev/null | grep -q . || systemctl status "$service_name" >/dev/null 2>&1; then
            if systemctl restart "$service_name" >/dev/null 2>&1; then
                restarted=1
            else
                echo -e "${YELLOW}⚠️ ${service_name} 重启失败，请稍后手动重启面板服务。${PLAIN}"
            fi
        fi
    done
    [[ "$restarted" -eq 1 ]] && echo -e "${GREEN}✅ 已重启 3x-ui/x-ui 面板服务，使域名设置生效。${PLAIN}"
}

update_xui_panel_domain_settings_for_single_443() {
    local old_domain="$1"
    local new_domain="$2"
    local db_path table_name backup_dir backup_file sql
    local checked=0 updated=0 failed=0 timestamp

    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "${CYAN}▶ 正在安装 sqlite3，用于同步 3x-ui 面板域名设置...${PLAIN}"
        install_pkg sqlite3 sqlite >/dev/null 2>&1 || true
    fi
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ 未检测到 sqlite3，跳过自动同步 3x-ui 面板域名设置。${PLAIN}"
        return 0
    fi

    timestamp=$(date +%Y%m%d_%H%M%S)
    while IFS= read -r db_path; do
        [[ -f "$db_path" ]] || continue
        table_name=$(sqlite3 "$db_path" "select name from sqlite_master where type='table' and name in ('settings','setting') order by case name when 'settings' then 0 else 1 end limit 1;" 2>/dev/null || true)
        [[ "$table_name" == "settings" || "$table_name" == "setting" ]] || continue
        checked=1

        backup_dir="/root/x-ui-backups"
        mkdir -p "$backup_dir"
        backup_file="${backup_dir}/x-ui.db.panel_domain_${timestamp}.bak"
        if ! sqlite3 "$db_path" ".backup '${backup_file}'" >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠️ 备份 3x-ui 数据库失败，跳过自动同步：${db_path}${PLAIN}"
            failed=1
            continue
        fi

        sql="
update ${table_name} set value='${new_domain}' where lower(key) in ('webdomain','subdomain');
update ${table_name} set value='https://${new_domain}${SUB_URI_PATH}' where lower(key)='suburi';
update ${table_name} set value='https://${new_domain}${CLASH_URI_PATH}' where lower(key)='subclashuri';
update ${table_name} set value=replace(replace(value,'https://${old_domain}','https://${new_domain}'),'http://${old_domain}','https://${new_domain}') where lower(key)='subjsonuri' and value like '%${old_domain}%';
"
        if sqlite3 "$db_path" "$sql" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ 已同步 3x-ui 面板/订阅域名设置：${db_path}${PLAIN}"
            echo -e "${CYAN}数据库备份：${backup_file}${PLAIN}"
            updated=1
        else
            echo -e "${YELLOW}⚠️ 同步 3x-ui 面板域名设置失败：${db_path}${PLAIN}"
            failed=1
        fi
    done < <(find_xui_database_candidates)

    [[ "$updated" -eq 1 ]] && restart_xui_panel_services_after_setting_update
    if [[ "$failed" -eq 1 ]]; then
        echo -e "${RED}❌ 3x-ui 面板域名设置未完整同步，已停止修改 443 面板域名。${PLAIN}"
        return 1
    fi
    if [[ "$checked" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️ 未找到 3x-ui 数据库，跳过 3x-ui 面板内部域名同步。${PLAIN}"
    fi
    return 0
}

edit_sni_stack_panel_subscription_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改 3x-ui 面板 / 订阅端口与路径${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}适用于：你在 3x-ui 里修改了面板端口、订阅端口、普通订阅路径或 Clash/Mihomo 路径。${PLAIN}"
    echo -e "${YELLOW}注意：3x-ui 3.x 新安装请选择 Skip SSL / 不申请 SSL；2.x 或旧配置仍需清空证书、订阅设置里的证书路径，Caddy 才能按 HTTP 反代。${PLAIN}"
    echo -e "${YELLOW}修改前请先在 3x-ui 面板里保存对应设置，再来这里同步脚本。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "当前面板后端：${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    echo -e "当前面板公网路径：${PANEL_WEB_PATH}"
    echo -e "当前订阅后端：${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}"
    echo -e "当前普通订阅路径：${SUB_URI_PATH}"
    echo -e "当前 Clash/Mihomo 路径：${CLASH_URI_PATH}"
    echo -e "------------------------------------------------"

    PANEL_LISTEN_ADDR=$(ask_with_default "3x-ui 面板监听地址" "$PANEL_LISTEN_ADDR")
    PANEL_LISTEN_PORT=$(ask_with_default "3x-ui 面板端口" "$PANEL_LISTEN_PORT")
    PANEL_WEB_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui 面板公网路径 / webBasePath" "$PANEL_WEB_PATH")")
    SUB_LISTEN_ADDR=$(ask_with_default "3x-ui 订阅服务监听地址" "$SUB_LISTEN_ADDR")
    SUB_LISTEN_PORT=$(ask_with_default "3x-ui 订阅服务端口" "$SUB_LISTEN_PORT")
    SUB_URI_PATH=$(normalize_path_prefix "$(ask_with_default "普通订阅路径前缀（不带客户端 Subscription，建议写 /sub/）" "$SUB_URI_PATH")")
    CLASH_URI_PATH=$(normalize_path_prefix "$(ask_with_default "Clash/Mihomo 订阅路径前缀（不带客户端 Subscription，建议写 /clash/）" "$CLASH_URI_PATH")")

    is_valid_listen_addr "$PANEL_LISTEN_ADDR" || { echo -e "${RED}❌ 面板监听地址无效：${PANEL_LISTEN_ADDR}${PLAIN}"; return 1; }
    is_valid_listen_addr "$SUB_LISTEN_ADDR" || { echo -e "${RED}❌ 订阅监听地址无效：${SUB_LISTEN_ADDR}${PLAIN}"; return 1; }
    is_valid_port "$PANEL_LISTEN_PORT" || { echo -e "${RED}❌ 面板端口无效：${PANEL_LISTEN_PORT}${PLAIN}"; return 1; }
    is_valid_port "$SUB_LISTEN_PORT" || { echo -e "${RED}❌ 订阅端口无效：${SUB_LISTEN_PORT}${PLAIN}"; return 1; }
    is_valid_path_prefix "$PANEL_WEB_PATH" || { echo -e "${RED}❌ 面板公网路径无效：${PANEL_WEB_PATH}${PLAIN}"; return 1; }
    is_valid_path_prefix "$SUB_URI_PATH" || { echo -e "${RED}❌ 普通订阅路径无效：${SUB_URI_PATH}${PLAIN}"; return 1; }
    is_valid_path_prefix "$CLASH_URI_PATH" || { echo -e "${RED}❌ Clash/Mihomo 路径无效：${CLASH_URI_PATH}${PLAIN}"; return 1; }
    if [[ "$PANEL_WEB_PATH" == "$SUB_URI_PATH" || "$PANEL_WEB_PATH" == "$CLASH_URI_PATH" || "$SUB_URI_PATH" == "$CLASH_URI_PATH" ]]; then
        echo -e "${RED}❌ 面板路径、普通订阅路径、Clash/Mihomo 路径不能相同。${PLAIN}"
        return 1
    fi
    warn_if_public_bind "3x-ui 面板" "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT" || return 1
    warn_if_public_bind "3x-ui 订阅服务" "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT" || return 1

    save_and_offer_reapply_sni_stack
}

edit_sni_stack_reality_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改 REALITY 本地监听与伪装 SNI${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}适用于：你在 3x-ui REALITY 入站里修改了监听端口、监听地址，或更换了伪装 SNI。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "当前 REALITY：${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    echo -e "当前 REALITY SNI：${REALITY_SNI}"
    echo -e "------------------------------------------------"

    local reality_sni_input
    XRAY_LISTEN_ADDR=$(ask_with_default "Xray/3x-ui REALITY 本地监听地址" "$XRAY_LISTEN_ADDR")
    XRAY_LISTEN_PORT=$(ask_with_default "Xray/3x-ui REALITY 本地监听端口" "$XRAY_LISTEN_PORT")
    reality_sni_input=$(ask_with_default "REALITY 伪装 SNI" "$REALITY_SNI")
    REALITY_SNI=$(normalize_domain_input "$reality_sni_input")

    is_valid_listen_addr "$XRAY_LISTEN_ADDR" || { echo -e "${RED}❌ REALITY 监听地址无效：${XRAY_LISTEN_ADDR}${PLAIN}"; return 1; }
    is_valid_port "$XRAY_LISTEN_PORT" || { echo -e "${RED}❌ REALITY 端口无效：${XRAY_LISTEN_PORT}${PLAIN}"; return 1; }
    is_valid_domain "$REALITY_SNI" || { print_domain_validation_error "REALITY SNI" "$reality_sni_input" "$REALITY_SNI"; return 1; }
    [[ "$REALITY_SNI" == "$PANEL_DOMAIN" ]] && { echo -e "${RED}❌ REALITY SNI 不能写面板域名。${PLAIN}"; return 1; }
    local existing
    for existing in "${SITE_DOMAINS[@]}" "${TCP_ROUTE_SNIS[@]}" "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$REALITY_SNI" == "$existing" ]] && { echo -e "${RED}❌ REALITY SNI 不能和其他 443 分流域名相同：${existing}${PLAIN}"; return 1; }
    done
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    probe_reality_sni "$REALITY_SNI" || return 1

    save_and_offer_reapply_sni_stack
}

edit_sni_stack_entry_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改 443 入口 / Web 反代监听${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    local web_label
    web_label=$(web_proxy_engine_label)
    echo -e "${YELLOW}适用于：你要调整公网入口端口、Web 反代本地 TLS 端口，或修正监听地址。普通用户建议保持默认。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "当前公网入口：${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT}"
    echo -e "当前 ${web_label} 本地 TLS：${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}"
    echo -e "------------------------------------------------"

    NGINX_LISTEN_ADDR=$(ask_with_default "Nginx 公网监听地址" "$NGINX_LISTEN_ADDR")
    NGINX_LISTEN_PORT=$(ask_with_default "Nginx 公网监听端口" "$NGINX_LISTEN_PORT")
    CADDY_LISTEN_ADDR=$(ask_with_default "${web_label}监听地址" "$CADDY_LISTEN_ADDR")
    CADDY_LISTEN_PORT=$(ask_with_default "${web_label}监听端口" "$CADDY_LISTEN_PORT")

    is_valid_listen_addr "$NGINX_LISTEN_ADDR" || { echo -e "${RED}❌ Nginx 监听地址无效：${NGINX_LISTEN_ADDR}${PLAIN}"; return 1; }
    is_valid_listen_addr "$CADDY_LISTEN_ADDR" || { echo -e "${RED}❌ Web 反代监听地址无效：${CADDY_LISTEN_ADDR}${PLAIN}"; return 1; }
    is_valid_port "$NGINX_LISTEN_PORT" || { echo -e "${RED}❌ Nginx 端口无效：${NGINX_LISTEN_PORT}${PLAIN}"; return 1; }
    is_valid_port "$CADDY_LISTEN_PORT" || { echo -e "${RED}❌ Web 反代端口无效：${CADDY_LISTEN_PORT}${PLAIN}"; return 1; }
    warn_if_public_bind "$web_label" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    if [[ "$NGINX_LISTEN_PORT" != "443" ]]; then
        echo -e "${YELLOW}⚠️  Nginx 公网入口不是 443。请确认云安全组、防火墙和客户端地址都同步改了。${PLAIN}"
    fi

    save_and_offer_reapply_sni_stack
}

edit_sni_stack_panel_domain_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改面板域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    if [[ ! -f "$cf_env_file" ]]; then
        echo -e "${RED}❌ 未找到 Cloudflare Token，请先到证书维护菜单更新 Token。${PLAIN}"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$cf_env_file"
    if [[ -z "${CF_Token:-}" ]]; then
        echo -e "${RED}❌ Cloudflare Token 为空，请先到证书维护菜单更新。${PLAIN}"
        return 1
    fi

    local old_domain new_domain new_domain_input existing confirm old_conf
    old_domain="$PANEL_DOMAIN"
    echo -e "当前面板域名：${old_domain}"
    echo -e "${YELLOW}修改前请先把新域名解析到当前 VPS，并确认 Cloudflare Token 有该 zone 权限。${PLAIN}"
    new_domain_input=$(ask_with_default "新的面板域名" "$PANEL_DOMAIN")
    new_domain=$(normalize_domain_input "$new_domain_input")
    [[ "$new_domain" == "$old_domain" ]] && { echo -e "${BLUE}面板域名未变化。${PLAIN}"; return 0; }
    is_valid_domain "$new_domain" || { print_domain_validation_error "面板域名" "$new_domain_input" "$new_domain"; return 1; }
    [[ "$new_domain" == "$REALITY_SNI" ]] && { echo -e "${RED}❌ 面板域名不能和 REALITY SNI 相同。${PLAIN}"; return 1; }
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$new_domain" == "$existing" ]] && { echo -e "${RED}❌ 面板域名不能和网站/反代域名相同。${PLAIN}"; return 1; }
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$new_domain" == "$existing" ]] && { echo -e "${RED}❌ 面板域名不能和 TCP/SNI 入站域名相同。${PLAIN}"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$new_domain" == "$existing" ]] && { echo -e "${RED}❌ 面板域名不能和 Xray 入站域名相同。${PLAIN}"; return 1; }
    done
    check_domain_dns_sanity "$new_domain" "新的面板域名" "prompt" || return 1
    confirm_risk_action "替换 443 面板域名为 ${new_domain}" \
        "面板域名、证书和 Caddy/Nginx 相关配置" \
        "使用 443 单入口备份恢复旧域名配置" \
        "确认新域名 DNS 已解析到当前 VPS，且 Token 有该 zone 权限。" || return 1

    issue_and_install_cert_for_domain "$new_domain" "$CF_Token" || return 1
    update_xui_panel_domain_settings_for_single_443 "$old_domain" "$new_domain" || return 1
    old_conf="/etc/caddy/conf.d/${old_domain}.caddy"
    [[ -f "$old_conf" ]] && quarantine_path "$old_conf" "/etc/caddy/conf.d_quarantine" >/dev/null 2>&1 || true
    PANEL_DOMAIN="$new_domain"
    rename_sni_ip_whitelist_domain "$old_domain" "$new_domain"
    save_and_offer_reapply_sni_stack
}

edit_sni_stack_runtime_profile() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🧭 修改 443 分流参数${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：后续修改面板域名、面板端口/路径、订阅端口/路径、REALITY SNI、入口端口时使用。${PLAIN}"
        echo -e "${YELLOW}新增网站请走 [19] -> [8]，不用重跑首次配置。${PLAIN}"
        echo -e "------------------------------------------------"
        if load_sni_stack_env >/dev/null 2>&1; then
            print_sni_stack_current_summary
        else
            echo -e "${RED}未找到 443 配置，请先运行 [19] -> [2]。${PLAIN}"
            return 1
        fi
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 修改面板/订阅端口与路径${PLAIN}"
        echo -e "${GREEN}  2. 修改 REALITY 本地监听 / 伪装 SNI${PLAIN}"
        echo -e "${GREEN}  3. 修改 Nginx 公网入口 / Web 反代本地 TLS${PLAIN}"
        echo -e "${GREEN}  4. 修改面板域名${PLAIN}"
        echo -e "${GREEN}  5. 重新应用当前保存的配置${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "👉 请选择要修改的配置: "
        case "$choice" in
            1) edit_sni_stack_panel_subscription_profile ;;
            2) edit_sni_stack_reality_profile ;;
            3) edit_sni_stack_entry_profile ;;
            4) edit_sni_stack_panel_domain_profile ;;
            5) reapply_sni_stack_from_env ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择。${PLAIN}"; sleep 1 ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

reapply_sni_stack_from_env() {
    load_sni_stack_env || return 1
    if [[ "${1:-}" != "--yes" ]]; then
        print_sni_stack_preview || return 1
    fi
    reapply_current_entry_mode --yes
}
