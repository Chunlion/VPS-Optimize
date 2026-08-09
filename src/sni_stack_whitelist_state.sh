# shellcheck shell=bash
# 443 stack domain membership, whitelist state, and basic health helpers.

is_sni_stack_managed_domain() {
    local domain="$1"
    local site_domain
    [[ "$domain" == "$PANEL_DOMAIN" ]] && return 0
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    for site_domain in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    for site_domain in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    return 1
}

is_sni_stack_web_domain() {
    local domain="$1"
    local site_domain
    [[ "$domain" == "$PANEL_DOMAIN" ]] && return 0
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    return 1
}

nginx_var_suffix_for_domain() {
    local domain="$1"
    domain=$(echo "$domain" | tr '.-' '__' | tr -cd 'a-zA-Z0-9_')
    printf '%s' "$domain"
}

normalize_sni_ip_whitelist_arrays() {
    local domains_input="${SNI_IP_WHITELIST_DOMAINS_CSV:-}"
    local ranges_input="${SNI_IP_WHITELIST_RANGES_PIPE:-}"
    local -a raw_domains=()
    local -a raw_ranges=()
    local -a clean_domains=()
    local -a clean_ranges=()
    local -a range_array=()
    local i domain ranges

    SNI_IP_WHITELIST_DOMAINS=()
    SNI_IP_WHITELIST_RANGES=()

    [[ -n "$domains_input" ]] && split_csv_to_array "$domains_input" raw_domains
    [[ -n "$ranges_input" ]] && split_pipe_to_array "$ranges_input" raw_ranges

    for i in "${!raw_domains[@]}"; do
        domain=$(normalize_domain_input "${raw_domains[$i]}")
        ranges="${raw_ranges[$i]:-}"
        [[ -n "$domain" && -n "$ranges" ]] || continue
        is_valid_domain "$domain" || continue
        is_sni_stack_web_domain "$domain" || continue
        if normalize_ip_whitelist_input "$ranges" range_array; then
            clean_domains+=("$domain")
            clean_ranges+=("$(join_array_by_space "${range_array[@]}")")
        fi
    done

    SNI_IP_WHITELIST_DOMAINS=("${clean_domains[@]}")
    SNI_IP_WHITELIST_RANGES=("${clean_ranges[@]}")
}

sni_ip_whitelist_index() {
    local domain="$1"
    local i
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        [[ "$domain" == "${SNI_IP_WHITELIST_DOMAINS[$i]}" ]] && { echo "$i"; return 0; }
    done
    return 1
}

sni_ip_whitelist_ranges_for_domain() {
    local domain="$1"
    local idx
    idx=$(sni_ip_whitelist_index "$domain" 2>/dev/null) || return 0
    echo "${SNI_IP_WHITELIST_RANGES[$idx]:-}"
}

set_sni_ip_whitelist_for_domain() {
    local domain="$1"
    local ranges="$2"
    local idx
    idx=$(sni_ip_whitelist_index "$domain" 2>/dev/null) || idx=""
    if [[ -n "$idx" ]]; then
        SNI_IP_WHITELIST_RANGES[$idx]="$ranges"
    else
        SNI_IP_WHITELIST_DOMAINS+=("$domain")
        SNI_IP_WHITELIST_RANGES+=("$ranges")
    fi
}

remove_sni_ip_whitelist_for_domain() {
    local domain="$1"
    local i
    local -a new_domains=()
    local -a new_ranges=()
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        [[ "$domain" == "${SNI_IP_WHITELIST_DOMAINS[$i]}" ]] && continue
        new_domains+=("${SNI_IP_WHITELIST_DOMAINS[$i]}")
        new_ranges+=("${SNI_IP_WHITELIST_RANGES[$i]}")
    done
    SNI_IP_WHITELIST_DOMAINS=("${new_domains[@]}")
    SNI_IP_WHITELIST_RANGES=("${new_ranges[@]}")
}

rename_sni_ip_whitelist_domain() {
    local old_domain="$1"
    local new_domain="$2"
    local idx
    idx=$(sni_ip_whitelist_index "$old_domain" 2>/dev/null) || return 0
    SNI_IP_WHITELIST_DOMAINS[$idx]="$new_domain"
}

print_sni_ip_whitelist_summary() {
    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "IP 白名单：  未启用" "IP Whitelist: Not enabled" "Белый список IP: не включен")"
        return 0
    fi

    local i
    echo -e "$(localized_text "IP 白名单：" "IP whitelist:" "Белый список IP:")"
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        echo -e "$(localized_text "  - ${SNI_IP_WHITELIST_DOMAINS[$i]} 仅允许：${SNI_IP_WHITELIST_RANGES[$i]}" "- ${SNI_IP_WHITELIST_DOMAINS[$i]} Only allowed: ${SNI_IP_WHITELIST_RANGES[$i]}" "- ${SNI_IP_WHITELIST_DOMAINS[$i]} Разрешено только: ${SNI_IP_WHITELIST_RANGES[$i]}")"
    done
}

sni_stack_health_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧪 443端口复用链路体检${PLAIN}" "${BOLD}🧪 Port 443 Reuse routing link health check${PLAIN}" "${BOLD}🧪 Проверка маршрутизации повторного использования порта 443${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local current_mode
    current_mode=$(get_entry_mode)
    if [[ "$current_mode" != "nginx-stream" ]]; then
        sni_stack_health_check_enhanced
        return $?
    fi

    local ok=0 warn=0 fail=0
    check_listen() {
        local name="$1"
        local port="$2"
        local expect_addr="$3"
        if ss -lntp 2>/dev/null | grep -q ":${port}[[:space:]]"; then
            local line
            line=$(ss -lntp 2>/dev/null | grep ":${port}[[:space:]]" | head -n1)
            echo -e "$(localized_text "${GREEN}✅ ${name} 端口 ${port} 有监听：${line}${PLAIN}" "${GREEN}✅ ${name} port ${port} is monitored: ${line}${PLAIN}" "${GREEN}✅ ${name} Порт ${port} контролируется: ${line}${PLAIN}")"
            if [[ -n "$expect_addr" ]] && ! echo "$line" | grep -q "$expect_addr"; then
                echo -e "$(localized_text "${YELLOW}⚠️ ${name} 期望监听 ${expect_addr}:${port}，请确认是否被改成公网监听。${PLAIN}" "${YELLOW}⚠️ ${name} is expected to monitor ${expect_addr}:${port}, please confirm whether it has been changed to Internet listening.${PLAIN}" "${YELLOW}⚠️ ${name} планирует отслеживать ${expect_addr}:${port}. Пожалуйста, подтвердите, был ли он изменен на прослушивание публичной сети.${PLAIN}")"
                ((warn++))
            else
                ((ok++))
            fi
        else
            echo -e "$(localized_text "${RED}❌ ${name} 端口 ${port} 未监听。${PLAIN}" "${RED}❌ ${name} Port ${port} is not listening.${PLAIN}" "${RED}❌ ${name} Порт ${port} не прослушивается.${PLAIN}")"
            ((fail++))
        fi
    }

    check_listen "$(localized_text "Nginx 公网入口" "Nginx public entry" "Nginx вход в публичную сеть")" "$NGINX_LISTEN_PORT" ""
    check_listen "$(localized_text "$(web_proxy_engine_label) 本地 TLS" "$(web_proxy_engine_label) local TLS" "$(web_proxy_engine_label) локальный TLS")" "$CADDY_LISTEN_PORT" "$CADDY_LISTEN_ADDR"
    check_listen "Xray / 3x-ui+Reality" "$XRAY_LISTEN_PORT" "$XRAY_LISTEN_ADDR"
    check_listen "$(localized_text "3x-ui 面板" "3x-ui panel" "Панель 3x-ui")" "$PANEL_LISTEN_PORT" "$PANEL_LISTEN_ADDR"
    check_listen "$(localized_text "3x-ui 订阅" "3x-ui Subscribe" "3x-ui Подписаться")" "$SUB_LISTEN_PORT" "$SUB_LISTEN_ADDR"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            check_listen "$(localized_text "网站后端 ${SITE_DOMAINS[$i]}" "Website backend ${SITE_DOMAINS[$i]}" "бэкенд сайта ${SITE_DOMAINS[$i]}")" "${SITE_BACKEND_PORTS[$i]}" "${SITE_BACKEND_ADDRS[$i]}"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            check_listen "$(localized_text "TCP/SNI 入站 ${TCP_ROUTE_SNIS[$tcp_i]}" "TCP/SNI Inbound ${TCP_ROUTE_SNIS[$tcp_i]}" "TCP/SNI Входящий ${TCP_ROUTE_SNIS[$tcp_i]}")" "${TCP_ROUTE_PORTS[$tcp_i]}" "${TCP_ROUTE_ADDRS[$tcp_i]}"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            check_listen "$(localized_text "Xray 入站 ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}" "Xray Inbound ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}" "Xray Входящий ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}")" "${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}"
        done
    fi

    echo -e "------------------------------------------------"
    if check_xui_cert_settings_for_single_443; then
        ((ok++))
    else
        ((warn++))
    fi

    echo -e "------------------------------------------------"
    if check_domain_dns_sanity "$PANEL_DOMAIN" "$(localized_text "面板域名" "Panel domain" "Доменное имя панели")" "warn"; then
        ((ok++))
    else
        ((warn++))
    fi
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local dns_site
        for dns_site in "${SITE_DOMAINS[@]}"; do
            [[ -z "$dns_site" ]] && continue
            if check_domain_dns_sanity "$dns_site" "$(localized_text "网站/反代域名" "Website/reverse domain" "Веб-сайт/обратное доменное имя")" "warn"; then
                ((ok++))
            else
                ((warn++))
            fi
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_sni
        for tcp_sni in "${TCP_ROUTE_SNIS[@]}"; do
            [[ -z "$tcp_sni" ]] && continue
            if check_domain_dns_sanity "$tcp_sni" "$(localized_text "TCP/SNI 入站域名" "TCP/SNI inbound domain" "TCP/SNI имя входящего домена")" "warn"; then
                ((ok++))
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 如果客户端使用服务器 IP 连接并手动指定 SNI，可忽略该 DNS 警告。${PLAIN}" "${YELLOW}⚠️ This DNS warning can be ignored if the client connects using the server IP and manually specifies SNI.${PLAIN}" "${YELLOW}⚠️ Это предупреждение DNS можно игнорировать, если клиент подключается с использованием IP-адреса сервера и вручную указывает SNI.${PLAIN}")"
                ((warn++))
            fi
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_sni
        for xray_route_sni in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
            [[ -z "$xray_route_sni" ]] && continue
            if check_domain_dns_sanity "$xray_route_sni" "$(localized_text "Xray 入站域名" "Xray inbound domain" "Xray входящее доменное имя")" "warn"; then
                ((ok++))
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 如果客户端使用服务器 IP 连接并手动指定 SNI，可忽略该 DNS 警告。${PLAIN}" "${YELLOW}⚠️ This DNS warning can be ignored if the client connects using the server IP and manually specifies SNI.${PLAIN}" "${YELLOW}⚠️ Это предупреждение DNS можно игнорировать, если клиент подключается с использованием IP-адреса сервера и вручную указывает SNI.${PLAIN}")"
                ((warn++))
            fi
        done
    fi

    echo -e "------------------------------------------------"
    nginx -t >/dev/null 2>&1 && echo -e "$(localized_text "${GREEN}✅ nginx -t 通过${PLAIN}" "${GREEN}✅ nginx -t by${PLAIN}" "${GREEN}✅ nginx -t от${PLAIN}")" && ((ok++)) || { echo -e "$(localized_text "${RED}❌ nginx -t 失败${PLAIN}" "${RED}❌ nginx -t failed${PLAIN}" "${RED}❌ nginx -t не удалось${PLAIN}")"; ((fail++)); }
    if [[ "$(current_web_proxy_engine)" == "caddy" ]]; then
        caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 && echo -e "$(localized_text "${GREEN}✅ Caddy 配置校验通过${PLAIN}" "${GREEN}✅ Caddy configuration validation passed${PLAIN}" "${GREEN}✅ Проверка конфигурации Caddy пройдена${PLAIN}")" && ((ok++)) || { echo -e "$(localized_text "${RED}❌ Caddy 配置校验失败${PLAIN}" "${RED}❌ Caddy configuration validation failed${PLAIN}" "${RED}❌ Caddy Проверка конфигурации не удалась${PLAIN}")"; ((fail++)); }
    fi
    if grep -Eq '^[[:space:]]*server_tokens[[:space:]]+off;' /etc/nginx/nginx.conf 2>/dev/null; then
        echo -e "$(localized_text "${GREEN}✅ Nginx 已关闭版本号显示 server_tokens off${PLAIN}" "${GREEN}✅ Nginx Version number display has been turned off server_tokens off${PLAIN}" "${GREEN}✅ Nginx Отображение номера версии отключено server_tokens off${PLAIN}")"
        ((ok++))
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未确认 Nginx server_tokens off，错误页可能显示版本号。${PLAIN}" "${YELLOW}⚠️ Not confirmed Nginx server_tokens off, the error page may display the version number.${PLAIN}" "${YELLOW}⚠️ Не подтверждено. Nginx server_tokens отключен, на странице ошибки может отображаться номер версии.${PLAIN}")"
        ((warn++))
    fi
    if [[ -f /etc/nginx/conf.d/00-vps-default-drop.conf ]]; then
        echo -e "$(localized_text "${GREEN}✅ Nginx 80 默认站点已设置为丢弃连接${PLAIN}" "${GREEN}✅ Nginx 80 The default site has been set to drop connections${PLAIN}" "${GREEN}✅ Nginx 80 Сайт по умолчанию настроен на отбрасывание соединений${PLAIN}")"
        ((ok++))
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未找到 80 默认丢弃配置，错误域名可能命中默认页。${PLAIN}" "${YELLOW}⚠️ Not found 80 default discard configuration, wrong domain may hit the default page.${PLAIN}" "${YELLOW}⚠️ Не найдено 80. Конфигурация отмены по умолчанию, неправильное доменное имя может попасть на страницу по умолчанию.${PLAIN}")"
        ((warn++))
    fi

    if command -v openssl >/dev/null 2>&1; then
        if timeout 10 openssl s_client -connect "127.0.0.1:${NGINX_LISTEN_PORT}" -servername "$PANEL_DOMAIN" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
            echo -e "$(localized_text "${GREEN}✅ 面板 SNI 可从入口命中 Web 反代引擎证书链${PLAIN}" "${GREEN}✅ Panel SNI can hit the Web reverse proxy engine certificate chain from the entry${PLAIN}" "${GREEN}✅ Панель SNI может попасть в цепочку сертификатов механизма обратного веб-прокси  со входа.${PLAIN}")"
            ((ok++))
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 面板 SNI 测试未拿到证书，请检查入口模式与 Web 反代引擎。${PLAIN}" "${YELLOW}⚠️ Panel SNI test did not get the certificate, please check the entry mode and Web reverse proxy engine.${PLAIN}" "${YELLOW}⚠️ Тест панели SNI не получил сертификат, проверьте режим входа и механизм веб-прокси.${PLAIN}")"
            ((warn++))
        fi
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "体检结果：${GREEN}通过 ${ok}${PLAIN} / ${YELLOW}警告 ${warn}${PLAIN} / ${RED}失败 ${fail}${PLAIN}" "health check results: ${GREEN}Passed ${ok}${PLAIN} / ${YELLOW}Warning ${warn}${PLAIN} / ${RED}Failed ${fail}${PLAIN}" "Результаты медицинского осмотра: ${GREEN}прошел ${ok}${PLAIN} / ${YELLOW}предупреждение ${warn}${PLAIN} / ${RED}не прошел ${fail}${PLAIN}")"
}
