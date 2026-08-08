# shellcheck shell=bash
# 443 stack env persistence, firewall hardening, result output, and runtime apply.

save_sni_stack_env() {
    mkdir -p /etc/vps-optimize
    local entry_mode site_domains_csv site_backend_addrs_csv site_backend_ports_csv
    local tcp_route_snis_csv tcp_route_addrs_csv tcp_route_ports_csv
    local sni_ip_whitelist_domains_csv sni_ip_whitelist_ranges_pipe
    entry_mode="${ENTRY_MODE:-$(get_entry_mode)}"
    case "$entry_mode" in
        "nginx_stream") entry_mode="nginx-stream" ;;
        "xray_fallback") entry_mode="xray-fallback" ;;
        "tcp_peek") entry_mode="tcp-peek" ;;
    esac
    case "$entry_mode" in
        "nginx-stream"|"xray-fallback"|"tcp-peek") ;;
        *) entry_mode="nginx-stream" ;;
    esac
    site_domains_csv=$(IFS=','; echo "${SITE_DOMAINS[*]}")
    site_backend_addrs_csv=$(IFS=','; echo "${SITE_BACKEND_ADDRS[*]}")
    site_backend_ports_csv=$(IFS=','; echo "${SITE_BACKEND_PORTS[*]}")
    tcp_route_snis_csv=$(IFS=','; echo "${TCP_ROUTE_SNIS[*]}")
    tcp_route_addrs_csv=$(IFS=','; echo "${TCP_ROUTE_ADDRS[*]}")
    tcp_route_ports_csv=$(IFS=','; echo "${TCP_ROUTE_PORTS[*]}")
    sni_ip_whitelist_domains_csv=$(IFS=','; echo "${SNI_IP_WHITELIST_DOMAINS[*]}")
    sni_ip_whitelist_ranges_pipe=$(IFS='|'; echo "${SNI_IP_WHITELIST_RANGES[*]}")
    cat <<EOF > /etc/vps-optimize/sni-stack.env
ENTRY_MODE='${entry_mode}'
PANEL_DOMAIN='${PANEL_DOMAIN}'
SITE_DOMAIN='${SITE_DOMAINS[0]:-}'
SITE_DOMAINS_CSV='${site_domains_csv}'
REALITY_SNI='${REALITY_SNI}'
NGINX_LISTEN_ADDR='${NGINX_LISTEN_ADDR}'
NGINX_LISTEN_PORT='${NGINX_LISTEN_PORT}'
CADDY_LISTEN_ADDR='${CADDY_LISTEN_ADDR}'
CADDY_LISTEN_PORT='${CADDY_LISTEN_PORT}'
XRAY_LISTEN_ADDR='${XRAY_LISTEN_ADDR}'
XRAY_LISTEN_PORT='${XRAY_LISTEN_PORT}'
XRAY_FALLBACK_MAIN_SNI='${XRAY_FALLBACK_MAIN_SNI:-}'
XRAY_FALLBACK_MAIN_ADDR='${XRAY_FALLBACK_MAIN_ADDR:-}'
XRAY_FALLBACK_MAIN_PORT='${XRAY_FALLBACK_MAIN_PORT:-}'
PANEL_LISTEN_ADDR='${PANEL_LISTEN_ADDR}'
PANEL_LISTEN_PORT='${PANEL_LISTEN_PORT}'
PANEL_WEB_PATH='${PANEL_WEB_PATH}'
SUB_LISTEN_ADDR='${SUB_LISTEN_ADDR}'
SUB_LISTEN_PORT='${SUB_LISTEN_PORT}'
SUB_URI_PATH='${SUB_URI_PATH}'
CLASH_URI_PATH='${CLASH_URI_PATH}'
SITE_BACKEND_ADDR='${SITE_BACKEND_ADDRS[0]:-127.0.0.1}'
SITE_BACKEND_PORT='${SITE_BACKEND_PORTS[0]:-3000}'
SITE_BACKEND_ADDRS_CSV='${site_backend_addrs_csv}'
SITE_BACKEND_PORTS_CSV='${site_backend_ports_csv}'
TCP_ROUTE_SNIS_CSV='${tcp_route_snis_csv}'
TCP_ROUTE_ADDRS_CSV='${tcp_route_addrs_csv}'
TCP_ROUTE_PORTS_CSV='${tcp_route_ports_csv}'
SNI_IP_WHITELIST_DOMAINS_CSV='${sni_ip_whitelist_domains_csv}'
SNI_IP_WHITELIST_RANGES_PIPE='${sni_ip_whitelist_ranges_pipe}'
EOF
    chmod 600 /etc/vps-optimize/sni-stack.env
}

harden_single_443_firewall() {
    local yn ssh_port remove_ports port
    echo -e "$(localized_text "${YELLOW}可选：防火墙只保留 SSH 与 Nginx 公网入口端口。${PLAIN}" "${YELLOW}Is optional: the firewall only reserves SSH and Nginx public entry ports.${PLAIN}" "${YELLOW}является необязательным: межсетевой экран резервирует только порты входа в публичную сеть SSH и Nginx.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}提醒：若 3x-ui 仍监听 0.0.0.0:${PANEL_LISTEN_PORT}，脚本的“自动追加当前活动端口”功能可能再次放行它。${PLAIN}" "${YELLOW}Reminder: if 3x-ui still listens on 0.0.0.0:${PANEL_LISTEN_PORT}, automatic active-port detection may allow that port again.${PLAIN}" "${YELLOW}Напоминание: если 3x-ui по-прежнему слушает 0.0.0.0:${PANEL_LISTEN_PORT}, автоматическое обнаружение активных портов может снова разрешить этот порт.${PLAIN}")"
    read_trimmed yn "$(localized_text "是否现在收紧防火墙？(Y/n，默认 y): " "Tighten the firewall now? (Y/n, default y):" "Ужесточить брандмауэр сейчас? (Да/нет, по умолчанию y):")"
    [[ "$yn" =~ ^[Yy]$ ]] || return 0
    ssh_port=$(ss -lntp 2>/dev/null | awk '/sshd/ {print $4}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' | head -n1)
    ssh_port=${ssh_port:-22}
    remove_ports=("$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT" "${SITE_BACKEND_PORTS[@]}" "${TCP_ROUTE_PORTS[@]}" "${XRAY_SNI_ROUTE_PORTS[@]}" "40000" "8443" "1443" "2096" "3000")
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || true
        ufw allow "${NGINX_LISTEN_PORT}/tcp" >/dev/null 2>&1 || true
        for port in "${remove_ports[@]}"; do
            [[ "$port" == "$ssh_port" || "$port" == "$NGINX_LISTEN_PORT" ]] && continue
            ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
            ufw delete allow "${port}/udp" >/dev/null 2>&1 || true
        done
    elif command -v firewall-cmd >/dev/null 2>&1; then
        systemctl enable --now firewalld >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="${ssh_port}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="${NGINX_LISTEN_PORT}/tcp" >/dev/null 2>&1 || true
        for port in "${remove_ports[@]}"; do
            [[ "$port" == "$ssh_port" || "$port" == "$NGINX_LISTEN_PORT" ]] && continue
            firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1 || true
            firewall-cmd --permanent --remove-port="${port}/udp" >/dev/null 2>&1 || true
        done
        firewall-cmd --reload >/dev/null 2>&1 || true
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 ufw/firewalld，跳过防火墙收紧。${PLAIN}" "${YELLOW}⚠️ ufw/firewalld not detected, skipping firewall tightening.${PLAIN}" "${YELLOW}⚠️ ufw/firewalld не обнаружен, пропускается ужесточение брандмауэра.${PLAIN}")"
    fi
}

print_sni_stack_result() {
    local check_ports=()
    local check_regex=""
    local p entry_mode entry_label entry_listener
    entry_mode="${ENTRY_MODE:-nginx-stream}"
    entry_mode=$(normalize_entry_mode_name "$entry_mode" 2>/dev/null || echo "nginx-stream")
    case "$entry_mode" in
        "nginx-stream") entry_label="$(localized_text "Nginx Stream 模式" "Nginx Stream mode" "Режим Nginx Stream")"; entry_listener="nginx" ;;
        "xray-fallback") entry_label="$(localized_text "Xray Fallback 模式" "Xray Fallback mode" "Xray Резервный режим")"; entry_listener="$(localized_text "xray/3x-ui 主入站" "xray/3x-ui main inbound" "xray/3x-ui основной входящий")" ;;
        "tcp-peek") entry_label="$(localized_text "TCP Peek + Splice 模式" "TCP Peek + Splice mode" "Режим TCP Peek + Splice")"; entry_listener="$(localized_text "vpso-mux 分流器" "vpso-mux routing" "vpso-mux маршрутизация")" ;;
        *) entry_label="$entry_mode"; entry_listener="$entry_mode" ;;
    esac
    check_ports=("$NGINX_LISTEN_PORT" "$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT" "${SITE_BACKEND_PORTS[@]}" "${TCP_ROUTE_PORTS[@]}" "${XRAY_SNI_ROUTE_PORTS[@]}")
    mapfile -t check_ports < <(printf '%s\n' "${check_ports[@]}" | grep -E '^[0-9]+$' | awk '!seen[$0]++')
    for p in "${check_ports[@]}"; do
        if [[ -z "$check_regex" ]]; then
            check_regex=":${p}([[:space:]]|$)"
        else
            check_regex="${check_regex}|:${p}([[:space:]]|$)"
        fi
    done

    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${GREEN}✅ 443 单入口分流配置完成${PLAIN}" "${GREEN}✅ 443 Shared entry route configuration completed${PLAIN}" "${GREEN}443 Конфигурация маршрутизации с одним входом завершена${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "当前入口模式：${entry_label} (${entry_mode})" "Current entry mode: ${entry_label} (${entry_mode})" "Текущий режим ввода: ${entry_label} (${entry_mode})")"
    echo -e "$(localized_text "${BOLD}一、以后从外面只访问这些地址${PLAIN}" "${BOLD}1. In the future, only these addresses will be accessed from the outside.${PLAIN}" "${BOLD}1. В дальнейшем доступ извне будет осуществляться только по этим адресам.${PLAIN}")"
    echo -e "$(localized_text "  面板入口：      https://${PANEL_DOMAIN}${PANEL_WEB_PATH}" "Panel entry: https://${PANEL_DOMAIN}${PANEL_WEB_PATH}" "Входная панель: https://${PANEL_DOMAIN}${PANEL_WEB_PATH}")"
    echo -e "$(localized_text "  普通订阅入口：  https://${PANEL_DOMAIN}${SUB_URI_PATH}" "Ordinary subscription entry: https://${PANEL_DOMAIN}${SUB_URI_PATH}" "Обычный вход по подписке: https://${PANEL_DOMAIN}${SUB_URI_PATH}.")"
    echo -e "  Clash/Mihomo：  https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            echo -e "$(localized_text "  网站/反代入口： https://${SITE_DOMAINS[$i]}/" "Website/reverse proxy entry: https://${SITE_DOMAINS[$i]}/" "Вход на сайт/обратный прокси: https://${SITE_DOMAINS[$i]}/")"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "  TCP/SNI 入站：  ${TCP_ROUTE_SNIS[$tcp_i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}" "TCP/SNI Inbound: ${TCP_ROUTE_SNIS[$tcp_i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}" "TCP/SNI Входящий: ${TCP_ROUTE_SNIS[$tcp_i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}")"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "  Xray 入站：     ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}:${NGINX_LISTEN_PORT} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "Xray Inbound: ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}:${NGINX_LISTEN_PORT} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "Xray Входящий: ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}:${NGINX_LISTEN_PORT} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}")"
        done
    fi
    echo -e "$(localized_text "  REALITY 端口：  ${NGINX_LISTEN_PORT}" "REALITY Port: ${NGINX_LISTEN_PORT}" "REALITY Порт: ${NGINX_LISTEN_PORT}")"
    echo -e ""
    echo -e "$(localized_text "${YELLOW}不要从公网访问这些内部端口：${CADDY_LISTEN_PORT}/${XRAY_LISTEN_PORT}/${PANEL_LISTEN_PORT}/${SUB_LISTEN_PORT}/${SITE_BACKEND_PORTS[*]} ${TCP_ROUTE_PORTS[*]} ${XRAY_SNI_ROUTE_PORTS[*]}${PLAIN}" "${YELLOW}Do not access these internal ports from the public: ${CADDY_LISTEN_PORT}/${XRAY_LISTEN_PORT}/${PANEL_LISTEN_PORT}/${SUB_LISTEN_PORT}/${SITE_BACKEND_PORTS[*]} ${TCP_ROUTE_PORTS[*]} ${XRAY_SNI_ROUTE_PORTS[*]}${PLAIN}" "${YELLOW}Не обращайтесь к этим внутренним портам из публичной сети: ${CADDY_LISTEN_PORT}/${XRAY_LISTEN_PORT}/${PANEL_LISTEN_PORT}/${SUB_LISTEN_PORT}/${SITE_BACKEND_PORTS[*]} ${TCP_ROUTE_PORTS[*]} ${XRAY_SNI_ROUTE_PORTS[*]}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}它们应该只给本机内部服务互相连接，不是浏览器入口。${PLAIN}" "${YELLOW}They should only connect the internal services of this machine to each other, not the browser entry.${PLAIN}" "${YELLOW}Они должны соединять между собой только внутренние службы этой машины, а не вход в браузер.${PLAIN}")"
    echo -e ""
    echo -e "$(localized_text "${BOLD}二、3x-ui 面板设置建议${PLAIN}" "${BOLD}2. 3x-ui panel setting recommendation${PLAIN}" "${BOLD}2. 3x-ui Рекомендации по настройке панели${PLAIN}")"
    echo -e "$(localized_text "  面板监听地址：${PANEL_LISTEN_ADDR}" "Panel listening address: ${PANEL_LISTEN_ADDR}" "Адрес прослушивания панели: ${PANEL_LISTEN_ADDR}")"
    echo -e "$(localized_text "  面板端口：    ${PANEL_LISTEN_PORT}" "Panel port: ${PANEL_LISTEN_PORT}" "Порт панели: ${PANEL_LISTEN_PORT}")"
    echo -e "  webBasePath： ${PANEL_WEB_PATH}"
    echo -e "$(localized_text "  面板证书路径/私钥路径：清空" "Panel certificate path/private key path: Clear" "Путь сертификата панели/путь закрытого ключа: Очистить")"
    echo -e "$(localized_text "  Web 反代引擎后端连接：http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Web reverse proxy engine backend connection: http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Серверное соединение механизма веб-прокси: http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}")"
    echo -e "  Panel URL / Public URL / External URL：https://${PANEL_DOMAIN}${PANEL_WEB_PATH}"
    echo -e "  Subscription URI Path：${SUB_URI_PATH}"
    echo -e "  Subscription External URL：https://${PANEL_DOMAIN}${SUB_URI_PATH}"
    echo -e "  Clash/Mihomo URI Path：${CLASH_URI_PATH}"
    echo -e "  Clash/Mihomo External URL：https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    echo -e "$(localized_text "${YELLOW}  不建议使用 webBasePath=/，随机面板路径能降低被批量扫描命中的概率。${PLAIN}" "${YELLOW}It is not recommended to use webBasePath=/. Random panel paths can reduce the probability of being hit by batch scanning.${PLAIN}" "${YELLOW}Не рекомендуется использовать webBasePath=/. Случайное расположение панелей может снизить вероятность попадания в пакетное сканирование.${PLAIN}")"
    echo -e "$(localized_text "  订阅证书路径/私钥路径：清空" "Subscription certificate path/private key path: clear" "Путь сертификата подписки/путь закрытого ключа: очистить")"
    echo -e ""
    echo -e "$(localized_text "${BOLD}三、Xray / 3x-ui REALITY 入站这样填${PLAIN}" "${BOLD}3. Xray / 3x-ui REALITY Enter like this${PLAIN}" "${BOLD}3. Xray / 3x-ui REALITY Введите вот так${PLAIN}")"
    echo -e "$(localized_text "  入站监听地址 listen：${XRAY_LISTEN_ADDR}" "Inbound listening address listen: ${XRAY_LISTEN_ADDR}" "Адрес прослушивания входящего подключения: ${XRAY_LISTEN_ADDR}")"
    echo -e "$(localized_text "  入站监听端口 port：  ${XRAY_LISTEN_PORT}" "Inbound listening port port: ${XRAY_LISTEN_PORT}" "Порт входящего прослушивания: ${XRAY_LISTEN_PORT}")"
    echo -e "$(localized_text "  协议 protocol：      VLESS" "Protocol protocol: VLESS" "Протокол протокола: VLESS")"
    echo -e "$(localized_text "  传输 network：       tcp" "Transmission network: tcp" "Сеть передачи: tcp")"
    echo -e "$(localized_text "  安全 security：      reality" "Security security: reality" "Безопасность безопасности: reality")"
    echo -e "  REALITY dest：       ${REALITY_SNI}:443"
    echo -e "  serverNames：        ${REALITY_SNI}"
    echo -e "  SpiderX：            /"
    echo -e "$(localized_text "  客户端连接地址：     你的服务器 IP 或解析到服务器的域名" "Client connection address: Your server IP or domain resolved to the server" "Адрес подключения клиента: IP-адрес вашего сервера или доменное имя, разрешенное серверу.")"
    echo -e "$(localized_text "  客户端连接端口：     ${NGINX_LISTEN_PORT}" "Client connection port: ${NGINX_LISTEN_PORT}" "Порт подключения клиента: ${NGINX_LISTEN_PORT}")"
    echo -e "$(localized_text "  客户端 SNI/serverName：${REALITY_SNI}" "Client SNI/serverName: ${REALITY_SNI}" "Клиент SNI/имя сервера: ${REALITY_SNI}")"
    echo -e "$(localized_text "${YELLOW}  注意：REALITY 的 dest/serverNames 必须是外部真实站点，不要写面板域名。${PLAIN}" "${YELLOW}Note: The dest/serverNames of REALITY must be an external real site, do not write the panel domain.${PLAIN}" "${YELLOW}Примечание. Имена dest/serverName для REALITY должны быть внешним реальным сайтом, не записывайте имя домена панели.${PLAIN}")"
    echo -e ""
    echo -e "$(localized_text "${BOLD}四、常见错误怎么判断${PLAIN}" "${BOLD}4. How to judge common errors${PLAIN}" "${BOLD}4. Как определить типичные ошибки${PLAIN}")"
    echo -e "$(localized_text "  ERR_SSL_PROTOCOL_ERROR：通常是访问了内部端口，外部只访问 https://${PANEL_DOMAIN}${PANEL_WEB_PATH}" "ERR_SSL_PROTOCOL_ERROR: Usually the internal port is accessed, and only https://${PANEL_DOMAIN}${PANEL_WEB_PATH} is accessed externally." "ERR_SSL_PROTOCOL_ERROR: Обычно осуществляется доступ к внутреннему порту, и только к https://${PANEL_DOMAIN}${PANEL_WEB_PATH} осуществляется внешний доступ.")"
    echo -e "$(localized_text "  ERR_TOO_MANY_REDIRECTS：通常是 3x-ui 面板或订阅证书路径没清空，或外部地址/路径配置不一致" "ERR_TOO_MANY_REDIRECTS: Usually the 3x-ui panel or subscription certificate path is not cleared, or the external address/path configuration is inconsistent" "ERR_TOO_MANY_REDIRECTS: Обычно путь к панели 3x-ui или сертификату подписки не очищается, или конфигурация внешнего адреса/пути несовместима.")"
    echo -e "$(localized_text "  HTTP 404：先检查访问路径是否等于 3x-ui 的 webBasePath，再检查 Caddy 是否反代到 ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "HTTP 404: First check whether the access path is equal to the webBasePath of 3x-ui, and then check whether Caddy is reversed to ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "HTTP 404: сначала проверьте, равен ли путь доступа webBasePath 3x-ui, а затем проверьте, не изменен ли Caddy на ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}.")"
    echo -e "$(localized_text "  502 Bad Gateway：通常是 3x-ui 没启动、端口不对，或 3x-ui 后端仍是 HTTPS" "502 Bad Gateway: Usually 3x-ui is not started, the port is wrong, or 3x-ui backend is still HTTPS" "502 Bad Gateway: обычно 3x-ui не запускается, порт неправильный или бэкенд 3x-ui все еще остается HTTPS.")"
    echo -e ""
    echo -e "$(localized_text "${BOLD}五、入口与后端配置${PLAIN}" "${BOLD}5. Entry and backend configuration${PLAIN}" "${BOLD}5. Входная и серверная конфигурация${PLAIN}")"
    echo -e "  ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${entry_listener}"
    echo -e "  ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> caddy"
    echo -e "  ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT} -> xray"
    echo -e "  ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} -> 3x-ui"
    echo -e "  ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT} -> 3x-ui subscription"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            echo -e "$(localized_text "  ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]} -> ${SITE_DOMAINS[$i]} 网站后端" "${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]} -> ${SITE_DOMAINS[$i]} website backend" "${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]} -> ${SITE_DOMAINS[$i]} бэкенд веб-сайта")"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "  ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]} -> ${TCP_ROUTE_SNIS[$tcp_i]} TCP/SNI 入站" "${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]} -> ${TCP_ROUTE_SNIS[$tcp_i]} TCP/SNI inbound" "${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]} -> ${TCP_ROUTE_SNIS[$tcp_i]} TCP/SNI входящий")"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "  ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} Xray 入站" "${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} Xray inbound" "${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} Xray входящий")"
        done
    fi
    echo -e ""
    echo -e "$(localized_text "${BOLD}六、检查命令${PLAIN}" "${BOLD}6. Check command${PLAIN}" "${BOLD}6. Проверьте команду.${PLAIN}")"
    if [[ -n "$check_regex" ]]; then
        echo -e "  ss -lntp | grep -E '${check_regex}'"
    else
        echo -e "  ss -lntp"
    fi
    echo -e "  nginx -t"
    echo -e "  caddy validate --config /etc/caddy/Caddyfile"
    echo -e "  curl -I http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}/"
    echo -e "$(localized_text "  openssl s_client -connect 服务器IP:${NGINX_LISTEN_PORT} -servername ${PANEL_DOMAIN}" "openssl s_client -connect server IP:${NGINX_LISTEN_PORT} -servername ${PANEL_DOMAIN}" "openssl s_client -IP-адрес сервера подключения: ${NGINX_LISTEN_PORT} -имя_сервера ${PANEL_DOMAIN}")"
    echo -e "$(localized_text "  openssl s_client -connect 服务器IP:${NGINX_LISTEN_PORT} -servername ${REALITY_SNI}" "openssl s_client -connect server IP:${NGINX_LISTEN_PORT} -servername ${REALITY_SNI}" "openssl s_client -IP-адрес сервера подключения: ${NGINX_LISTEN_PORT} -имя_сервера ${REALITY_SNI}")"
    echo -e "  journalctl -u caddy -n 80 --no-pager"
    echo -e "  journalctl -u x-ui -u 3x-ui -n 80 --no-pager"
    echo -e ""
    case "$entry_mode" in
        "xray-fallback")
            echo -e "$(localized_text "${RED}绝对不要做：Caddy 直接监听公网 443；3x-ui 面板、订阅服务或额外本地入站暴露公网；3x-ui 证书路径未清空就跑 Web fallback；把 REALITY dest/serverNames 写成面板域名。${PLAIN}" "${RED}Do not: Caddy directly listens on the public port 443; 3x-ui panel, subscription service or additional local inbound exposes the public; 3x-ui runs Web fallback before the certificate path is cleared; write REALITY dest/serverNames as the panel domain.${PLAIN}" "${RED}не должен этого делать: Caddy напрямую прослушивает публичный порт 443; Панель 3x-ui, служба подписки или дополнительный локальное входящее подключение предоставляют доступ к публичной сети; 3x-ui запускает веб-резервный режим до того, как путь к сертификату будет очищен; напишите REALITY dest/serverNames в качестве имени домена панели.${PLAIN}")"
            ;;
        *)
            echo -e "$(localized_text "${RED}绝对不要做：Caddy 直接监听公网 443；Xray/3x-ui 主入站直接占用公网 443；3x-ui 面板或新增本地入站暴露公网；3x-ui 证书路径未清空就跑 443；把 REALITY dest/serverNames 写成面板域名。${PLAIN}" "${RED}Do not: Caddy directly listens on the public port 443; Xray/3x-ui directly occupies the public for the main inbound 443; 3x-ui panel or adds a new local inbound to expose the public; 3x-ui uses port 443 before clearing the certificate path; set REALITY dest/serverNames to the panel domain.${PLAIN}" "${RED}не должен этого делать: Caddy напрямую прослушивает публичный порт 443; Xray/3x-ui напрямую занимает публичную сеть для основного входящего 443; Панель 3x-ui или добавляет новый локальное входящее подключение для доступа к публичной сети; 3x-ui запускается без очистки пути сертификата 443; put REALITY dest/serverNames записывается как доменное имя панели.${PLAIN}")"
            ;;
    esac
}

apply_sni_stack_runtime_config() {
    local backup_dir current_mode
    current_mode="${ENTRY_MODE:-$(get_entry_mode)}"
    current_mode=$(normalize_entry_mode_name "$current_mode" 2>/dev/null || echo "nginx-stream")

    create_sni_stack_backup
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    guard_current_ssh_not_on_entry_port "$(localized_text "重新应用 443 单入口运行参数" "Reapply 443 Shared Entry Run Parameters" "Повторно применить 443 отдельных рабочих параметра")" || return 1
    check_entry_mode_dependencies "$current_mode" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "入口模式依赖检查失败" "Entry mode dependency check failed" "Проверка зависимости режима входа не удалась")"; return 1; }
    preflight_entry_mode_before_cutover "$current_mode" || { echo -e "$(localized_text "${RED}❌ 入口模式 ${current_mode} 预检失败，公网 443 未重新应用。${PLAIN}" "${RED}❌ entry mode ${current_mode} Preflight failed, public port 443 was not reapplied.${PLAIN}" "${RED}❌ Режим входа ${current_mode} Не удалось выполнить предварительную проверку, конфигурация публичного порта 443 не была применена повторно.${PLAIN}")"; return 1; }
    stop_public_443_entry_services_for_target "$current_mode" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "停止旧公网 443 入口服务失败" "Stop the old public port 443 entry service failed" "Остановить старую публичную сеть 443, служба входа не удалась")"; return 1; }
    apply_entry_mode_by_name "$current_mode" "$backup_dir" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "入口模式 ${current_mode} 应用失败" "Entry mode ${current_mode} application failed" "Режим входа в приложение ${current_mode} не выполнен.")"; return 1; }
    ENTRY_MODE="$current_mode"
    save_sni_stack_env
    write_single_443_engine_state "$(entry_mode_engine_name "$current_mode")" "$backup_dir"
    generate_caddy_cf_manifest
}
