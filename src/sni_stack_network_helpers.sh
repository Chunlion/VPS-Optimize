# shellcheck shell=bash
# 443 stack network, certificate-adjacent, and preview helpers.

detect_vps_public_ip_by_family() {
    local family="$1"
    local curl_flag="-4"
    local endpoint ip
    local endpoints=()

    command -v curl >/dev/null 2>&1 || return 1

    if [[ "$family" == "6" ]]; then
        curl_flag="-6"
        endpoints=("https://api6.ipify.org" "https://ipv6.icanhazip.com")
    else
        endpoints=("https://api.ipify.org" "https://ipv4.icanhazip.com")
    fi

    for endpoint in "${endpoints[@]}"; do
        ip=$(curl "$curl_flag" -fsS --connect-timeout 3 --max-time 5 "$endpoint" 2>/dev/null | tr -d '\r' | awk 'NF {print $1; exit}')
        ip=$(trim_input "$ip")
        if [[ "$family" == "6" ]]; then
            is_valid_ipv6_cidr "$ip" && { echo "$ip"; return 0; }
        else
            is_valid_ipv4_cidr "$ip" && ! is_suspicious_public_ipv4 "$ip" && { echo "$ip"; return 0; }
        fi
    done
    return 1
}

append_vps_public_ips_to_whitelist() {
    local -n out_array=$1
    local ip existing seen added=0
    seen=" "
    for existing in "${out_array[@]}"; do
        seen+=" ${existing} "
    done

    for ip in "$(detect_vps_public_ip_by_family 4 2>/dev/null)" "$(detect_vps_public_ip_by_family 6 2>/dev/null)"; do
        [[ -n "$ip" ]] || continue
        if [[ "$seen" != *" ${ip} "* ]]; then
            out_array+=("$ip")
            seen+=" ${ip} "
            echo -e "$(localized_text "${GREEN}✅ 已自动加入 VPS 本机公网 IP：${ip}${PLAIN}" "${GREEN}✅ has automatically joined the VPS. Local public IP: ${ip}${PLAIN}" "${GREEN}✅ автоматически присоединился к VPS. IP-адрес локальной публичной сети: ${ip}.${PLAIN}")"
            added=1
        fi
    done

    if [[ "$added" -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未能自动获取 VPS 本机公网 IP；如需要本机自测访问，请手动加入 VPS 公网 IP。${PLAIN}" "${YELLOW}⚠️ Failed to automatically obtain the VPS local public IP; if you need local self-test access, please manually add the VPS public IP.${PLAIN}" "${YELLOW}⚠️ Не удалось автоматически получить IP-адрес локальной публичной сети VPS; Если вам нужен локальный доступ для самотестирования, вручную добавьте IP-адрес публичной сети VPS.${PLAIN}")"
    fi

    append_local_service_ips_to_whitelist "$1" seen
}

append_local_service_ips_to_whitelist() {
    local -n out_array=$1
    local -n seen_ref=$2
    local entry subnet local_added=0
    local -a local_ranges=("127.0.0.1/32" "::1/128")

    if command -v docker >/dev/null 2>&1; then
        while IFS= read -r subnet; do
            subnet=$(trim_input "$subnet")
            [[ -n "$subnet" ]] && local_ranges+=("$subnet")
        done < <(docker network inspect $(docker network ls -q 2>/dev/null) \
            --format '{{range .IPAM.Config}}{{if .Subnet}}{{.Subnet}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | sort -u)
    fi

    for entry in "${local_ranges[@]}"; do
        [[ -n "$entry" ]] || continue
        is_valid_ip_cidr "$entry" || continue
        if [[ "$seen_ref" != *" ${entry} "* ]]; then
            out_array+=("$entry")
            seen_ref+=" ${entry} "
            echo -e "$(localized_text "${GREEN}✅ 已自动加入本机/容器访问来源：${entry}${PLAIN}" "${GREEN}✅ has been automatically added to this machine/container. Access source: ${entry}${PLAIN}" "${GREEN}вещество было автоматически добавлено в эту машину/контейнер. Источник доступа: ${entry}${PLAIN}")"
            local_added=1
        fi
    done

    if [[ "$local_added" -eq 0 ]]; then
        echo -e "$(localized_text "${BLUE}ℹ️ 本机/容器访问来源已在白名单中，无需重复加入。${PLAIN}" "${BLUE}ℹ️ The local/container access source is already in the whitelist and there is no need to add it again.${PLAIN}" "${BLUE}ℹ️ Локальный/контейнерный источник доступа уже находится в белом списке, и нет необходимости добавлять его снова.${PLAIN}")"
    fi
}

join_array_by_space() {
    local IFS=' '
    echo "$*"
}

detect_ssh_client_ip() {
    local client_ip=""
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        client_ip="${SSH_CONNECTION%% *}"
    elif [[ -n "${SSH_CLIENT:-}" ]]; then
        client_ip="${SSH_CLIENT%% *}"
    fi
    echo "$client_ip"
}

caddy_ip_whitelist_block() {
    local ranges="$1"
    [[ -z "$ranges" ]] && return 0
    cat <<EOF
    # vps-optimize-ip-whitelist-start
    @vps_ip_denied not remote_ip ${ranges}
    abort @vps_ip_denied
    # vps-optimize-ip-whitelist-end

EOF
}

find_xui_database_candidates() {
    local db_path extra_db
    local seen_dbs=" "
    local db_candidates=(
        "/etc/x-ui/x-ui.db"
        "/usr/local/x-ui/x-ui.db"
        "/usr/local/x-ui/bin/x-ui.db"
        "/etc/x-panel/x-panel.db"
    )

    for db_path in "${db_candidates[@]}"; do
        [[ -f "$db_path" ]] || continue
        [[ "$seen_dbs" == *" ${db_path} "* ]] && continue
        seen_dbs+=" ${db_path} "
        echo "$db_path"
    done

    while IFS= read -r extra_db; do
        [[ -f "$extra_db" ]] || continue
        [[ "$seen_dbs" == *" ${extra_db} "* ]] && continue
        seen_dbs+=" ${extra_db} "
        echo "$extra_db"
    done < <(find /etc /usr/local/x-ui /opt -maxdepth 4 -type f \( -name "x-ui.db" -o -name "x-panel.db" \) 2>/dev/null | sort -u)
}

check_xui_cert_settings_for_single_443() {
    local cert_key_sql db_path rows key value
    local checked=0 found=0

    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 sqlite3，跳过 3x-ui 证书路径数据库检查。${PLAIN}" "${YELLOW}⚠️ sqlite3 not detected, skipping 3x-ui certificate path database check.${PLAIN}" "${YELLOW}⚠️ sqlite3 не обнаружен, проверка базы данных пути сертификата 3x-ui пропускается.${PLAIN}")"
        return 2
    fi

    cert_key_sql=$(xui_cert_setting_key_sql_list)
    while IFS= read -r db_path; do
        [[ -n "$db_path" ]] || continue
        checked=1
        rows=$(sqlite3 -separator '|' "$db_path" "select key,value from settings where lower(key) in (${cert_key_sql}) and length(trim(coalesce(value,''))) > 0;" 2>/dev/null || true)
        [[ -n "$rows" ]] || continue

        found=1
        echo -e "$(localized_text "${YELLOW}⚠️ ${db_path} 仍有 3x-ui 面板/订阅证书路径，443端口复用下建议清空：${PLAIN}" "${YELLOW}⚠️ ${db_path} still has the 3x-ui panel/subscription certificate path, and it is recommended to clear it under the Port 443 Reuse:${PLAIN}" "${YELLOW}⚠️ ${db_path} по-прежнему имеет путь к сертификату панели/подписки 3x-ui, рекомендуется очистить одну запись 443:${PLAIN}")"
        while IFS='|' read -r key value; do
            [[ -n "$key" ]] || continue
            echo -e "  ${key}=${value}"
        done <<< "$rows"
    done < <(find_xui_database_candidates)

    if [[ "$checked" -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未找到 3x-ui 数据库，跳过证书路径检查。${PLAIN}" "${YELLOW}⚠️ 3x-ui database not found, skipping certificate path check.${PLAIN}" "${YELLOW}⚠️ База данных 3x-ui не найдена, проверка пути сертификата пропущена.${PLAIN}")"
        return 2
    fi

    if [[ "$found" -eq 1 ]]; then
        echo -e "$(localized_text "${YELLOW}建议：进入 [5 面板、节点与订阅工具] -> [3 面板 SSL 修复]，或在 3x-ui 面板里清空证书路径并重启。${PLAIN}" "${YELLOW}Recommendation: Go to [5 Panel, Node and Subscription Tool] -> [3 Panel SSL Repair], or clear the certificate path in the 3x-ui panel and restart.${PLAIN}" "${YELLOW}Рекомендация : перейдите к [5 Panel, Node and Subscription Tool] -> [3 Panel SSL Repair] или очистите путь к сертификату на панели 3x-ui и перезапустите.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "${GREEN}✅ 3x-ui 面板/订阅证书路径未发现残留${PLAIN}" "${GREEN}✅ 3x-ui Panel/subscription certificate path No residual found${PLAIN}" "${GREEN}✅ 3x-ui Путь сертификата панели/подписки Остатки не найдены${PLAIN}")"
    return 0
}

cleanup_old_nginx_sni_stream_configs() {
    mkdir -p /etc/nginx/stream.d
    local old_dir="/etc/nginx/stream.d/backup_vps_sni_$(date +%Y%m%d_%H%M%S)"
    local moved=0
    while IFS= read -r conf_file; do
        mkdir -p "$old_dir"
        mv "$conf_file" "$old_dir/" >/dev/null 2>&1 && ((moved++))
    done < <(find /etc/nginx/stream.d -maxdepth 1 -type f -name 'vps_sni_*.conf' 2>/dev/null | sort)
    if [[ "$moved" -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 已隔离 ${moved} 个旧 Nginx SNI 配置到：${old_dir}${PLAIN}" "${YELLOW}⚠️ Isolated ${moved} old Nginx SNI configured to: ${old_dir}${PLAIN}" "${YELLOW}⚠️ Изолированный ${moved} старый Nginx SNI настроен на: ${old_dir}${PLAIN}")"
    fi
}

probe_reality_sni() {
    local sni="$1"
    echo -e "$(localized_text "${CYAN}▶ 正在检测 REALITY 伪装 SNI 连通性：${sni}:443${PLAIN}" "${CYAN}▶ Detecting REALITY Disguise SNI Connectivity: ${sni}:443${PLAIN}" "${CYAN}▶ Обнаружение REALITY Маскировка SNI Связь: ${sni}:443${PLAIN}")"
    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 openssl，跳过 SNI 连通性检测。${PLAIN}" "${YELLOW}⚠️ openssl not detected, skipping SNI connectivity detection.${PLAIN}" "${YELLOW}⚠️ openssl не обнаружен, пропускается обнаружение подключения SNI.${PLAIN}")"
        return 0
    fi
    if timeout 12 openssl s_client -connect "${sni}:443" -servername "$sni" </dev/null 2>/tmp/vps_reality_sni_probe.log | grep -q "BEGIN CERTIFICATE"; then
        echo -e "$(localized_text "${GREEN}✅ REALITY SNI 可连通并返回证书。${PLAIN}" "${GREEN}✅ REALITY SNI can connect and return the certificate.${PLAIN}" "${GREEN}✅ REALITY SNI может подключиться и вернуть сертификат.${PLAIN}")"
        return 0
    fi
    echo -e "$(localized_text "${RED}❌ REALITY SNI 检测失败：${sni}:443 未正常返回证书。${PLAIN}" "${RED}❌ REALITY SNI Detection failed: ${sni}:443 The certificate was not returned normally.${PLAIN}" "${RED}❌ REALITY SNI Ошибка обнаружения: ${sni}:443 Сертификат не был возвращен обычным образом.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}请更换一个外部真实 HTTPS 站点域名，不要使用模板域名或自己的面板域名。${PLAIN}" "${YELLOW}Please replace it with an external real HTTPS site domain. Do not use a template domain or your own panel domain.${PLAIN}" "${YELLOW}Пожалуйста, замените его внешним реальным доменным именем сайта HTTPS. Не используйте доменное имя шаблона или собственное доменное имя панели.${PLAIN}")"
    return 1
}

print_sni_stack_preview() {
    local entry_mode entry_label
    entry_mode="${ENTRY_MODE:-nginx-stream}"
    entry_mode=$(normalize_entry_mode_name "$entry_mode" 2>/dev/null || echo "nginx-stream")
    case "$entry_mode" in
        "nginx-stream") entry_label="$(localized_text "Nginx Stream 模式" "Nginx Stream mode" "Режим Nginx Stream")" ;;
        "xray-fallback") entry_label="$(localized_text "Xray Fallback 模式" "Xray Fallback mode" "Xray Резервный режим")" ;;
        "tcp-peek") entry_label="$(localized_text "TCP Peek + Splice 模式 / vpso-mux 分流器" "TCP Peek + Splice mode / vpso-mux routing" "Режим TCP Peek + Splice / маршрутизация vpso-mux")" ;;
        *) entry_label="$entry_mode" ;;
    esac

    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}即将写入的 443端口复用配置预览${PLAIN}" "${BOLD}Preview of Port 443 Reuse route configuration to be written${PLAIN}" "${BOLD}Предварительный просмотр конфигурации маршрутизации повторного использования порта 443, которая будет записана${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "配置模式 ENTRY_MODE：${entry_mode}" "Configuration mode ENTRY_MODE: ${entry_mode}" "Режим конфигурации ENTRY_MODE: ${entry_mode}")"
    echo -e "$(localized_text "公网入口：${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${entry_label}" "public entry: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${entry_label}" "Вход в публичную сеть: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${entry_label}.")"
    echo -e "$(localized_text "面板域名：${PANEL_DOMAIN} -> ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Panel domain: ${PANEL_DOMAIN} -> ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Доменное имя панели: ${PANEL_DOMAIN} -> ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}")"
    echo -e "$(localized_text "面板路径：https://${PANEL_DOMAIN}${PANEL_WEB_PATH:-/panel/}" "Panel path: https://${PANEL_DOMAIN}${PANEL_WEB_PATH:-/panel/}" "Путь панели: https://${PANEL_DOMAIN}${PANEL_WEB_PATH:-/panel/}")"
    echo -e "$(localized_text "普通订阅路径：https://${PANEL_DOMAIN}${SUB_URI_PATH:-/sub/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Ordinary subscription path: https://${PANEL_DOMAIN}${SUB_URI_PATH:-/sub/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Обычный путь подписки: https://${PANEL_DOMAIN}${SUB_URI_PATH:-/sub/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}.")"
    echo -e "$(localized_text "Clash/Mihomo 路径：https://${PANEL_DOMAIN}${CLASH_URI_PATH:-/clash/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Clash/Mihomo Path: https://${PANEL_DOMAIN}${CLASH_URI_PATH:-/clash/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Clash/Mihomo Путь: https://${PANEL_DOMAIN}${CLASH_URI_PATH:-/clash/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}")"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            echo -e "$(localized_text "网站/反代域名：${SITE_DOMAINS[$i]} -> ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}" "Website/reverse domain: ${SITE_DOMAINS[$i]} -> ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}" "Веб-сайт/обратное доменное имя: ${SITE_DOMAINS[$i]} -> ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}")"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "TCP/SNI 入站：${TCP_ROUTE_SNIS[$tcp_i]} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}" "TCP/SNI Inbound: ${TCP_ROUTE_SNIS[$tcp_i]} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}" "TCP/SNI Входящий: ${TCP_ROUTE_SNIS[$tcp_i]} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}")"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "Xray 入站分流：${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "Xray Inbound offload: ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "Xray Входящая разгрузка: ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}")"
        done
    fi
    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}域名 IP 白名单：${PLAIN}" "${YELLOW}Domain IP whitelist:${PLAIN}" "${YELLOW}Белый список IP-адресов доменного имени :${PLAIN}")"
        local wl_i
        for wl_i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
            echo -e "$(localized_text "  ${SNI_IP_WHITELIST_DOMAINS[$wl_i]} 仅允许 ${SNI_IP_WHITELIST_RANGES[$wl_i]}" "${SNI_IP_WHITELIST_DOMAINS[$wl_i]} Only ${SNI_IP_WHITELIST_RANGES[$wl_i]} is allowed" "${SNI_IP_WHITELIST_DOMAINS[$wl_i]} Разрешен только ${SNI_IP_WHITELIST_RANGES[$wl_i]}.")"
        done
    fi
    if [[ "$entry_mode" == "xray-fallback" ]]; then
        echo -e "$(localized_text "Xray 主入站：公网 ${NGINX_LISTEN_PORT} 由 Xray 接管，普通 HTTPS fallback 到 ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}" "Xray main inbound: public ${NGINX_LISTEN_PORT} is taken over by Xray, ordinary HTTPS fallback to ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}" "Основной входящий Xray: публичная сеть ${NGINX_LISTEN_PORT} перехвачена Xray, обычный резерв HTTPS для ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}")"
        echo -e "$(localized_text "提示：脚本不会创建或修改 3x-ui/Xray 入站内部配置。" "Tip: The script does not create or modify the 3x-ui/Xray inbound internal configuration." "Совет: Скрипт не создает и не изменяет входящую внутреннюю конфигурацию 3x-ui/Xray.")"
    else
        echo -e "REALITY SNI：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
        echo -e "$(localized_text "默认/未知 SNI -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}" "Default/Unknown SNI -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}" "По умолчанию/Неизвестно SNI -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}")"
    fi
    echo -e ""
    echo -e "$(localized_text "${YELLOW}确认后会备份现有配置，并按所选 ENTRY_MODE 生成入口配置。${PLAIN}" "${YELLOW}After confirms, it will back up the existing configuration and generate the entry configuration according to the selected ENTRY_MODE.${PLAIN}" "${YELLOW}После подтверждения он создаст резервную копию существующей конфигурации и сгенерирует конфигурацию записи в соответствии с выбранным ENTRY_MODE.${PLAIN}")"
    confirm_risk_action "$(localized_text "写入 443端口复用配置" "Write Port 443 Reuse configuration" "Запишите общую конфигурацию с повторным использованием порта 443.")" \
        "$(localized_text "${entry_label}、Caddy 配置和 443 分流规则" "${entry_label}, Caddy configuration and 443 routing rules" "Конфигурация ${entry_label}, Caddy и 443 правила маршрутизирования")" \
        "$(localized_text "使用本次自动备份目录恢复，或进入 443 维护菜单回滚" "Use this automatic backup directory to restore, or enter the 443 maintenance menu to roll back" "Используйте этот каталог автоматического резервного копирования для восстановления или войдите в меню обслуживания 443 для отката.")" \
        "$(localized_text "确认公网 443 没有其他服务需要直接占用。" "Confirm that no other services on public port 443 need to be directly occupied." "Убедитесь, что никакие другие службы для публичного порта 443 не должны быть заняты напрямую.")"
}

caddy_format_configs() {
    command -v caddy >/dev/null 2>&1 || return 0
    caddy fmt --overwrite /etc/caddy/Caddyfile >/dev/null 2>&1 || true
    if [[ -d /etc/caddy/conf.d ]]; then
        while IFS= read -r conf_file; do
            caddy fmt --overwrite "$conf_file" >/dev/null 2>&1 || true
        done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)
    fi
}
