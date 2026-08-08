# shellcheck shell=bash
# 443 single entry point health checks, HTTP/TLS probes, and subscription hints.

print_443_health_status_code_hints() {
    echo -e "$(localized_text "${BOLD}状态码提示${PLAIN}" "${BOLD}Status code prompt${PLAIN}" "${BOLD}подсказка кода состояния${PLAIN}")"
    echo -e "$(localized_text "  - 403/401：可能是 Web 白名单、CDN/WAF、源站保护、Host/SNI 策略或后端鉴权。" "- 403/401: It may be web whitelist, CDN/WAF, origin protection, Host/SNI policy or backend authentication." "- 403/401: это может быть белый список веб-сайтов, CDN/WAF, защита источника, политика Host/SNI или внутренняя аутентификация.")"
    echo -e "$(localized_text "  - 502：可能是 Caddy 到后端端口不通。" "- 502: It may be that Caddy cannot reach the backend port." "- 502: Возможно, Caddy не может достичь внутреннего порта.")"
    echo -e "$(localized_text "  - 525/526：可能是 CDN 到源站 TLS 或证书校验失败。" "- 525/526: It may be that the CDN to the origin site TLS or the certificate verification failed." "- 525/526: Возможно, CDN к исходному сайту TLS или проверка сертификата не удалась.")"
    echo -e "$(localized_text "  - 超时：可能是 443 监听、防火墙、安全组、入口服务异常。" "- Timeout: It may be 443 abnormality in listening, firewall, security group, or entry service." "- Тайм-аут: это может быть ошибка 443 в прослушивании, брандмауэре, группе безопасности или службе точки входа.")"
}

print_443_health_reality_notes() {
    echo -e "$(localized_text "${BOLD}REALITY 检查提示${PLAIN}" "${BOLD}REALITY Inspection prompt${PLAIN}" "${BOLD}REALITY Запрос на проверку${PLAIN}")"
    echo -e "$(localized_text "  - 不要要求 REALITY serverName/dest 加入 Web 反代引擎。" "- Do not require REALITY serverName/dest to join the web reverse proxy engine." "- Не требуйте REALITY serverName/dest для присоединения к механизму веб-прокси.")"
    echo -e "$(localized_text "  - 不要要求本机证书覆盖 REALITY serverName。" "- Do not require native certificates to override REALITY serverName." "— Не требуйте собственных сертификатов для переопределения имени сервера REALITY.")"
    echo -e "$(localized_text "  - REALITY 应检查外部目标站点是否真实可访问、TLS 特征是否稳定。" "- REALITY should check whether the external target site is truly accessible and whether the TLS characteristics are stable." "- REALITY должен проверить, действительно ли внешний целевой сайт доступен и стабильны ли характеристики TLS.")"
    echo -e "$(localized_text "  - 普通 TLS 节点和 REALITY 节点的 SNI/serverName 检查逻辑必须区分。" "- The SNI/serverName check logic of ordinary TLS nodes and REALITY nodes must be distinguished." "- Необходимо различать логику проверки SNI/serverName обычных узлов TLS и узлов REALITY.")"
}

print_web_domain_http_status() {
    local label="$1"
    local domain="$2"
    local path="${3:-/}"
    local url code

    [[ -n "$domain" ]] || return 0
    path=$(normalize_path_prefix "$path")
    url="https://${domain}${path}"

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "$(localized_text "${label}：${url} -> ${YELLOW}未检测，curl 未安装${PLAIN}" "${label}: ${url} -> ${YELLOW}Is not detected, curl is not installed,${PLAIN} is not installed" "${label}: ${url} -> ${YELLOW}не обнаружен, curl не установлен,${PLAIN} не установлен")"
        return 0
    fi

    code=$(curl -k -L -o /dev/null -sS --connect-timeout 6 --max-time 12 -w '%{http_code}' "$url" 2>/dev/null) || code="timeout"
    [[ -z "$code" || "$code" == "000" ]] && code="timeout"
    echo -e "${label}：${url} -> ${code}"
}

print_domain_cert_file_status() {
    local domain="$1"
    local cert key root_cert root_key

    [[ -n "$domain" ]] || return 0
    cert="/etc/caddy/certs/${domain}.crt"
    key="/etc/caddy/certs/${domain}.key"
    root_cert="/root/cert/${domain}.crt"
    root_key="/root/cert/${domain}.key"

    echo -e "${CYAN}${domain}${PLAIN}"
    [[ -s "$cert" ]] && echo -e "$(localized_text "  ${GREEN}✅ 证书文件存在：${cert}${PLAIN}" "${GREEN}✅ Certificate file exists: ${cert}${PLAIN}" "${GREEN}✅ Файл сертификата существует: ${cert}${PLAIN}")" || echo -e "$(localized_text "  ${YELLOW}⚠️ 证书文件不存在或为空：${cert}${PLAIN}" "${YELLOW}⚠️ The certificate file does not exist or is empty: ${cert}${PLAIN}" "${YELLOW}⚠️ Файл сертификата не существует или пуст: ${cert}${PLAIN}.")"
    [[ -s "$key" ]] && echo -e "$(localized_text "  ${GREEN}✅ 私钥文件存在：${key}${PLAIN}" "${GREEN}✅ Private key file exists: ${key}${PLAIN}" "${GREEN}✅ Существует файл закрытого ключа: ${key}${PLAIN}.")" || echo -e "$(localized_text "  ${YELLOW}⚠️ 私钥文件不存在或为空：${key}${PLAIN}" "${YELLOW}⚠️ The private key file does not exist or is empty: ${key}${PLAIN}" "${YELLOW}⚠️ Файл закрытого ключа не существует или пуст: ${key}${PLAIN}.")"

    if [[ -L "$root_cert" && "$(readlink "$root_cert" 2>/dev/null)" == "$cert" && -e "$root_cert" ]]; then
        echo -e "$(localized_text "  ${GREEN}✅ /root/cert 证书软链接正常：${root_cert} -> ${cert}${PLAIN}" "${GREEN}✅ /root/cert certificate symlink is normal: ${root_cert} -> ${cert}${PLAIN}" "${GREEN}✅ /root/cert символическая ссылка сертификата является нормальной: ${root_cert} -> ${cert}${PLAIN}")"
    else
        echo -e "$(localized_text "  ${YELLOW}⚠️ /root/cert 证书软链接异常或不存在：${root_cert}${PLAIN}" "${YELLOW}⚠️ /root/cert Certificate symlink is abnormal or does not exist: ${root_cert}${PLAIN}" "${YELLOW}⚠️ /root/cert символическая ссылка на сертификат ненормальна или не существует: ${root_cert}${PLAIN}")"
    fi

    if [[ -L "$root_key" && "$(readlink "$root_key" 2>/dev/null)" == "$key" && -e "$root_key" ]]; then
        echo -e "$(localized_text "  ${GREEN}✅ /root/cert 私钥软链接正常：${root_key} -> ${key}${PLAIN}" "${GREEN}✅ /root/cert private key symlink is normal: ${root_key} -> ${key}${PLAIN}" "${GREEN}✅ /root/cert символическая ссылка на закрытый ключ является нормальной: ${root_key} -> ${key}${PLAIN}")"
    else
        echo -e "$(localized_text "  ${YELLOW}⚠️ /root/cert 私钥软链接异常或不存在：${root_key}${PLAIN}" "${YELLOW}⚠️ /root/cert The private key symlink is abnormal or does not exist: ${root_key}${PLAIN}" "${YELLOW}⚠️ /root/cert символическая ссылка на закрытый ключ ненормальна или не существует: ${root_key}${PLAIN}")"
    fi
}

print_xray_route_health_list() {
    local mode="$1"
    local i sni addr port line main_idx status

    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}未配置 Xray 入站分流规则：$(xray_sni_routes_path)${PLAIN}" "${YELLOW}No Xray inbound routing rules are configured: $(xray_sni_routes_path)${PLAIN}" "${YELLOW}Правила маршрутизации входящих подключений Xray не настроены: $(xray_sni_routes_path)${PLAIN}")"
        return 0
    fi

    main_idx=$(xray_fallback_main_route_index 2>/dev/null || true)
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        sni="${XRAY_SNI_ROUTE_SNIS[$i]}"
        addr="${XRAY_SNI_ROUTE_ADDRS[$i]}"
        port="${XRAY_SNI_ROUTE_PORTS[$i]}"
        [[ -n "$sni" ]] || continue

        if [[ "$mode" == "xray-fallback" ]]; then
            if [[ -n "$main_idx" && "$i" == "$main_idx" ]]; then
                status="$(localized_text "xray-fallback 主入站，当前模式生效" "xray-fallback Main inbound, current mode takes effect" "xray-fallback Основной входящий, текущий режим вступает в силу")"
            else
                status="$(localized_text "已保留，当前 xray-fallback 模式下不生效" "Reserved, not effective in current xray-fallback mode" "Зарезервировано, не действует в текущем резервном режиме xray.")"
            fi
        else
            status="$(localized_text "当前模式支持按 SNI 分流" "The current mode supports routinging according to SNI" "Текущий режим поддерживает маршрутизирование согласно SNI.")"
        fi

        echo -e "${CYAN}${sni}${PLAIN} -> ${addr}:${port}（${status}）"
        if [[ "${CADDY_LISTEN_PORT:-}" == "$port" ]]; then
            echo -e "$(localized_text "${RED}  ❌ 与 Web 反代引擎本地端口 ${CADDY_LISTEN_PORT} 冲突。${PLAIN}" "${RED}❌ Conflicts with the web inversion engine local port ${CADDY_LISTEN_PORT}.${PLAIN}" "${RED}❌ Конфликты с локальным портом ${CADDY_LISTEN_PORT} механизма веб-инверсии.${PLAIN}")"
        fi
        line=$(xray_route_listen_line_by_addr_port "$addr" "$port")
        if [[ -n "$line" ]]; then
            echo -e "$(localized_text "${GREEN}  ✅ 端口已监听：${line}${PLAIN}" "${GREEN}✅ Port is listening: ${line}${PLAIN}" "${GREEN}✅ Порт прослушивается: ${line}${PLAIN}")"
            if echo "$line" | grep -Eq '(^|[[:space:]])(0\.0\.0\.0|\*|\[::\]):'"${port}"'[[:space:]]'; then
                echo -e "$(localized_text "${YELLOW}  ⚠️ 检测到可能监听在 0.0.0.0/[::]，存在公网暴露风险，建议改为 127.0.0.1。${PLAIN}" "${YELLOW}⚠️ Detected that it may be monitored at 0.0.0.0/[::], which is a risk of Internet exposure. It is recommended to change it to 127.0.0.1.${PLAIN}" "${YELLOW}⚠️ Обнаружено, что его можно отслеживать по адресу 0.0.0.0/[::]. Существует риск публичного доступа. Рекомендуется изменить его на 127.0.0.1.${PLAIN}")"
            fi
        else
            echo -e "$(localized_text "${YELLOW}  ⚠️ 未检测到 ${addr}:${port} 监听，请先去 3x-ui 创建并启用对应入站。${PLAIN}" "${YELLOW}⚠️ The ${addr}:${port} monitor is not detected. Please go to 3x-ui first to create and enable the corresponding inbound connection.${PLAIN}" "${YELLOW}⚠️ Монитор ${addr}:${port} не обнаружен. Сначала перейдите по адресу 3x-ui, чтобы создать и включить соответствующее входящее соединение.${PLAIN}")"
        fi
    done
}

print_443_health_connlimit_scope_notice() {
    local marker runtime_rules saved_rules rules locations source_count

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}端口并发连接限制${PLAIN}" "${BOLD}Port concurrent connection limit${PLAIN}" "${BOLD}Ограничение количества одновременных подключений к порту${PLAIN}")"

    if ! declare -F port_connlimit_comment >/dev/null || ! declare -F port_connlimit_runtime_rule_fingerprints >/dev/null || ! declare -F port_connlimit_known_saved_rule_fingerprints >/dev/null; then
        echo -e "$(localized_text "${BLUE}未接入 connlimit 检测 helper，跳过端口并发连接限制检查。${PLAIN}" "${BLUE}Is not connected to the connlimit detection helper and skips the port concurrent connection limit check.${PLAIN}" "${BLUE}не подключен к помощнику обнаружения connlimit и пропускает проверку ограничения количества одновременных подключений к порту.${PLAIN}")"
        return 0
    fi

    marker=$(port_connlimit_comment 443)
    runtime_rules=$(port_connlimit_runtime_rule_fingerprints | grep -F "$marker" || true)
    saved_rules=$(port_connlimit_known_saved_rule_fingerprints | grep -F "$marker" || true)
    rules=$(printf '%s\n%s\n' "$runtime_rules" "$saved_rules" | grep -F "$marker" || true)

    if [[ -z "$rules" ]]; then
        echo -e "$(localized_text "${BLUE}未检测到本脚本添加的公网 443 connlimit 规则。${PLAIN}" "${BLUE}Did not detect the public port 443 connlimit rule added by this script.${PLAIN}" "${BLUE}не обнаружил правило connlimit публичного порта 443, добавленное этим сценарием.${PLAIN}")"
        return 0
    fi

    locations=""
    [[ -n "$runtime_rules" ]] && locations="$(localized_text "运行时" "runtime" "время выполнения")"
    [[ -n "$saved_rules" ]] && locations="$(localized_text "${locations:+${locations},}持久化文件" "${locations:+${locations},}persistent files" "${locations:+${locations},}постоянные файлы")"
    source_count=$(printf '%s\n' "$rules" | grep -c . || true)

    echo -e "$(localized_text "${YELLOW}检测到本脚本添加的公网 443 connlimit 规则：${marker}${PLAIN}" "${YELLOW}Detects the public port 443 connlimit rule added by this script: ${marker}${PLAIN}" "${YELLOW}обнаруживает правило connlimit публичного порта 443, добавленное этим скриптом: ${marker}${PLAIN}")"
    echo -e "$(localized_text "检测位置：${locations:-未知}；匹配条数：${source_count}" "Detection position: ${locations:-未知}; matching number: ${source_count}" "Позиция обнаружения: ${locations:-未知}; соответствующий номер: ${source_count}")"
    echo -e "$(localized_text "${RED}影响范围：该限制只能作用于整个公网 443 入口，不能精准到某个 SNI、Xray/3x-ui 入站、UUID 或用户。${PLAIN}" "${RED}Scope of influence: This restriction can only be applied to the entire public port 443 entry, and cannot be precise to a specific SNI, Xray/3x-ui inbound, UUID or user.${PLAIN}" "${RED}Область влияния : это ограничение может применяться только ко всему входу в публичный порт 443 и не может быть точным для конкретного входящего SNI, Xray/3x-ui, UUID или пользователя.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如果某个节点、订阅或网站被误伤，请到 [8 防火墙规则管理] -> [5 端口并发连接限制] 查看或删除公网 443 的 connlimit 规则。${PLAIN}" "${YELLOW}If a node, subscription or website is accidentally damaged, please go to [8 Firewall Rule Management] -> [5 Port Concurrent Connection Limit] to view or delete the connlimit rule of public port 443.${PLAIN}" "${YELLOW}Если узел, подписка или веб-сайт случайно повреждены, перейдите в раздел [8 Управление правилами брандмауэра] -> [Ограничение одновременных подключений через 5 портов], чтобы просмотреть или удалить правило connlimit публичного порта 443.${PLAIN}")"
}

sni_stack_health_check_enhanced() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧪 443 链路体检增强${PLAIN}" "${BOLD}🧪 443 Link health check enhancement${PLAIN}" "${BOLD}🧪 443 Улучшение проверки работоспособности ссылки${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    detect_current_entry_status

    local mode web_backend web_label xray_backend panel_backend sub_backend site_backend route_count ranges i domain public_443_lines mux_config mux_service
    mode="$ENTRY_STATUS_MODE"
    web_backend=$(web_proxy_backend)
    web_label=$(web_proxy_engine_label)
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    panel_backend=$(format_hostport "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT")
    sub_backend=$(format_hostport "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT")
    mux_config=$(vpso_mux_config_path)
    mux_service="/etc/systemd/system/$(vpso_mux_service_name)"
    route_count=$((2 + ${#SITE_DOMAINS[@]} + ${#TCP_ROUTE_SNIS[@]} + ${#XRAY_SNI_ROUTE_SNIS[@]}))

    echo -e "$(localized_text "${BOLD}入口状态${PLAIN}" "${BOLD}Entry status${PLAIN}" "${BOLD}Статус входа${PLAIN}")"
    echo -e "$(localized_text "当前 ENTRY_MODE：${GREEN}${mode}${PLAIN}" "Current ENTRY_MODE: ${GREEN}${mode}${PLAIN}" "Текущий ENTRY_MODE: ${GREEN}${mode}${PLAIN}")"
    print_entry_mode_compat_notice
    echo -e "$(localized_text "实际公网 443 监听服务：${ENTRY_STATUS_LISTENER_PROCESS}" "Actual public port 443 listening service: ${ENTRY_STATUS_LISTENER_PROCESS}" "Фактическая служба прослушивания публичного порта 443: ${ENTRY_STATUS_LISTENER_PROCESS}.")"
    public_443_lines=$(ss -lntp 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || true)
    echo -e "$(localized_text "${public_443_lines:-未监听或当前用户无权限查看进程}" "${public_443_lines:-未监听或当前用户无权限查看进程}" "${public_443_lines:-未监听或当前用户无权限查看进程}")"
    if [[ "$ENTRY_STATUS_CONSISTENT" == "yes" ]]; then
        echo -e "$(localized_text "配置模式与实际监听：${GREEN}一致${PLAIN}" "The configuration mode is consistent with the actual listening: ${GREEN}${PLAIN}" "Режим конфигурации соответствует фактическому прослушиваниеу: ${GREEN}${PLAIN}")"
    else
        echo -e "$(localized_text "配置模式与实际监听：${YELLOW}不一致${PLAIN}" "The configuration mode is inconsistent with the actual listening: ${YELLOW}${PLAIN}" "Режим конфигурации не соответствует реальному прослушиваниеу: ${YELLOW}${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}配置模式与实际监听不一致，建议重新应用当前入口模式。${PLAIN}" "${YELLOW}Configuration mode is inconsistent with actual listening. It is recommended to re-apply the current entry mode.${PLAIN}" "${YELLOW}Режим конфигурации несовместим с реальным прослушиваниеом. Рекомендуется повторно применить текущий режим входа.${PLAIN}")"
    fi
    echo -e "$(localized_text "nginx 状态：${ENTRY_STATUS_NGINX_SERVICE}" "nginx Status: ${ENTRY_STATUS_NGINX_SERVICE}" "Статус nginx: ${ENTRY_STATUS_NGINX_SERVICE}")"
    echo -e "$(localized_text "Xray/3x-ui 状态：${ENTRY_STATUS_XRAY_SERVICE}" "Xray/3x-ui Status: ${ENTRY_STATUS_XRAY_SERVICE}" "Xray/3x-ui Статус: ${ENTRY_STATUS_XRAY_SERVICE}")"
    echo -e "$(localized_text "TCP Peek + Splice 状态：${ENTRY_STATUS_TCPPEEK_SERVICE}" "TCP Peek + Splice Status: ${ENTRY_STATUS_TCPPEEK_SERVICE}" "Статус TCP Peek + Splice: ${ENTRY_STATUS_TCPPEEK_SERVICE}")"
    if [[ "$(current_web_proxy_engine)" == "caddy" ]]; then
        echo -e "$(localized_text "caddy 状态：$(service_status_compact caddy)" "caddy Status: $(service_status_compact caddy)" "Статус caddy: $(service_status_compact caddy)")"
    fi
    if [[ -f "$mux_config" ]]; then
        echo -e "$(localized_text "TCP Peek + Splice 分流规则：${GREEN}存在 ${mux_config}${PLAIN}" "TCP Peek + Splice routing rule: ${GREEN}Exists ${mux_config}${PLAIN}" "TCP Peek + Splice Правило перенаправления: ${GREEN}существует ${mux_config}${PLAIN}")"
    else
        echo -e "$(localized_text "TCP Peek + Splice 分流规则：${YELLOW}未找到 ${mux_config}${PLAIN}" "TCP Peek + Splice routing rule: ${YELLOW}Not found ${mux_config}${PLAIN}" "TCP Peek + Splice Правило перенаправления: ${YELLOW}не найден ${mux_config}${PLAIN}")"
    fi
    if [[ -f "$mux_service" ]]; then
        echo -e "$(localized_text "vpso-mux 分流器 systemd：${GREEN}存在 ${mux_service}${PLAIN}" "vpso-mux routing systemd: ${GREEN}Exists ${mux_service}${PLAIN}" "vpso-mux маршрутизация systemd: ${GREEN}существует ${mux_service}${PLAIN}")"
    else
        echo -e "$(localized_text "vpso-mux 分流器 systemd：${YELLOW}未找到 ${mux_service}${PLAIN}" "vpso-mux routing systemd: ${YELLOW}Not found ${mux_service}${PLAIN}" "маршрутизация vpso-mux systemd: ${YELLOW}не найден ${mux_service}${PLAIN}")"
    fi
    print_443_health_connlimit_scope_notice

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}本地监听${PLAIN}" "${BOLD}Local listeners${PLAIN}" "${BOLD}локальный прослушивание${PLAIN}")"
    echo -e "$(localized_text "Web 反代引擎本地监听端口：${web_backend} (${web_label})" "Web reverse proxy engine local listening port: ${web_backend} (${web_label})" "Локальный порт прослушивания механизма веб-прокси: ${web_backend} (${web_label})")"
    get_listen_line_by_port "$CADDY_LISTEN_PORT" | grep -q "$CADDY_LISTEN_ADDR" && echo -e "$(localized_text "${GREEN}✅ ${web_label} 期望监听 ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}${PLAIN}" "${GREEN}✅ ${web_label} expects to monitor ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}${PLAIN}" "${GREEN}✅ ${web_label} планирует контролировать ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}${PLAIN}")" || echo -e "$(localized_text "${YELLOW}⚠️ ${web_label} 监听地址需确认：$(get_listen_line_by_port "$CADDY_LISTEN_PORT")${PLAIN}" "${YELLOW}⚠️ ${web_label} The listening address needs to be confirmed: $(get_listen_line_by_port \"$CADDY_LISTEN_PORT\")${PLAIN}" "${YELLOW}⚠️ ${web_label} Необходимо подтвердить адрес прослушивания: $(get_listen_line_by_port \"$CADDY_LISTEN_PORT\")${PLAIN}")"
    echo -e "$(localized_text "Xray 本地监听端口：${xray_backend}" "Xray Local listening port: ${xray_backend}" "Xray Локальный порт прослушивания: ${xray_backend}")"
    get_listen_line_by_port "$XRAY_LISTEN_PORT" | grep -q "$XRAY_LISTEN_ADDR" && echo -e "$(localized_text "${GREEN}✅ Xray 期望监听 ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}${PLAIN}" "${GREEN}✅ Xray expects to monitor ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}${PLAIN}" "${GREEN}✅ Xray планирует контролировать ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}${PLAIN}")" || echo -e "$(localized_text "${YELLOW}⚠️ Xray 监听地址需确认：$(get_listen_line_by_port "$XRAY_LISTEN_PORT")${PLAIN}" "${YELLOW}⚠️ Xray The listening address needs to be confirmed: $(get_listen_line_by_port \"$XRAY_LISTEN_PORT\")${PLAIN}" "${YELLOW}⚠️ Xray Необходимо подтвердить адрес прослушивания: $(get_listen_line_by_port \"$XRAY_LISTEN_PORT\")${PLAIN}")"
    if [[ "$ENTRY_STATUS_LISTENER" == "xray" ]]; then
        echo -e "$(localized_text "Xray 公网监听端口：${GREEN}公网 443 当前由 Xray 监听${PLAIN}" "Xray Internet listening port: ${GREEN} public port 443 is currently monitored by Xray ${PLAIN}" "Порт прослушивания публичной сети Xray: публичный порт 443 ${GREEN}в настоящее время контролируется Xray${PLAIN}")"
    else
        echo -e "$(localized_text "Xray 公网监听端口：未检测到 Xray 监听公网 443" "Xray public listening port: not detected Xray listening public port 443" "Порт прослушивания публичной сети Xray: не обнаружен. Xray прослушивает публичный порт 443")"
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}网站后端连通性${PLAIN}" "${BOLD}Website backend connectivity${PLAIN}" "${BOLD}Подключение к серверной части веб-сайта${PLAIN}")"
    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo "$(localized_text "未配置自定义网站/反代后端。" "Custom website/reverse proxy backend not configured." "Пользовательский веб-сайт или бэкенд обратного прокси не настроены.")"
    else
        for i in "${!SITE_DOMAINS[@]}"; do
            domain="${SITE_DOMAINS[$i]}"
            [[ -n "$domain" ]] || continue
            probe_backend_target "$(localized_text "网站后端 ${domain}" "Website backend ${domain}" "бэкенд сайта ${domain}")" "${SITE_BACKEND_ADDRS[$i]}" "${SITE_BACKEND_PORTS[$i]}" || true
        done
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}Xray 入站分流规则${PLAIN}" "${BOLD}Xray Inbound routing rule${PLAIN}" "${BOLD}Правила маршрутизации входящих подключений Xray${PLAIN}")"
    if entry_mode_supports_xray_sni_routes "$mode"; then
        echo -e "$(localized_text "当前入口模式是否支持 Xray 入站分流规则：${GREEN}支持${PLAIN}" "Whether the current ingress mode supports Xray Inbound routing rules: ${GREEN}Supports${PLAIN}" "Поддерживает ли текущий режим входящего подключения Xray Правила маршрутизация входящего подключения: ${GREEN}поддерживает${PLAIN}")"
    else
        echo -e "$(localized_text "当前入口模式是否支持 Xray 入站分流规则：${YELLOW}不支持/当前不生效${PLAIN}" "Whether the current ingress mode supports Xray Inbound routing rules: ${YELLOW}Is not supported/currently not in effect${PLAIN}" "Поддерживает ли текущий режим входящего подключения Xray Правила маршрутизация входящего подключения: ${YELLOW}не поддерживается/в настоящее время не действует${PLAIN}")"
    fi
    if [[ "$mode" == "xray-fallback" ]]; then
        echo -e "$(localized_text "${YELLOW}当前为 Xray Fallback 模式，Xray 入站管理中的多 SNI 分流规则不生效。${PLAIN}" "${YELLOW}Xray Fallback mode is active; multi-SNI rules from Xray inbound management do not apply.${PLAIN}" "${YELLOW}Активен режим Xray Fallback; правила нескольких SNI из управления входящими подключениями Xray не действуют.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}如需多个本地 Xray 入站，请切换到 Nginx Stream 模式或 TCP Peek + Splice 模式。${PLAIN}" "${YELLOW}If you need multiple local Xray inbound, please switch to Nginx Stream mode or TCP Peek + Splice mode.${PLAIN}" "${YELLOW}Если вам нужно несколько локальных входящих Xray, переключитесь в режим Nginx Stream или режим TCP Peek + Splice.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}普通 HTTPS 流量会先进入 Xray，再 fallback 到所选 Web 反代引擎；403/拒绝访问通常优先排查 Web 白名单、CDN/WAF、源站保护、Cloudflare 回源限制或 Host/SNI 策略。${PLAIN}" "${YELLOW}Ordinary HTTPS traffic will first enter Xray and then fallback to the selected Web reverse proxy engine; 403/Access Denied usually prioritizes Web whitelisting, CDN/WAF, origin site protection, Cloudflare back-to-origin restrictions or Host/SNI policy.${PLAIN}" "${YELLOW}Обычный трафик HTTPS сначала поступает в Xray, а затем возвращается к выбранному механизму обратный прокси Web; 403/Доступ запрещен, обычно приоритет отдается белому списку веб-сайтов, CDN/WAF, защите исходного сайта, ограничениям возврата к исходному коду Cloudflare или политике Host/SNI.${PLAIN}")"
        print_xray_fallback_main_route_summary
    fi
    print_xray_route_health_list "$mode"

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}Web 域名白名单状态${PLAIN}" "${BOLD}Web domain whitelist status${PLAIN}" "${BOLD}Состояние белого списка веб-доменов${PLAIN}")"
    print_sni_ip_whitelist_summary
    echo -e "$(localized_text "Xray 节点白名单：不支持/不启用" "Xray node whitelist: not supported/not enabled" "Белый список узлов Xray: не поддерживается/не включен")"

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}证书文件与 /root/cert 软链接${PLAIN}" "${BOLD}Certificate file and /root/cert symlink${PLAIN}" "${BOLD}Файл сертификата и символическая ссылка /root/cert${PLAIN}")"
    print_domain_cert_file_status "$PANEL_DOMAIN"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        print_domain_cert_file_status "$domain"
    done

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}Web 域名访问 HTTP 状态码${PLAIN}" "${BOLD}Web domain access HTTP status code${PLAIN}" "${BOLD}Доступ к веб-доменному имени HTTP Код состояния${PLAIN}")"
    print_web_domain_http_status "$(localized_text "面板路径" "Panel path" "Путь панели")" "$PANEL_DOMAIN" "$PANEL_WEB_PATH"
    print_web_domain_http_status "$(localized_text "普通订阅路径" "Common subscription path" "Общий путь подписки")" "$PANEL_DOMAIN" "$SUB_URI_PATH"
    print_web_domain_http_status "$(localized_text "Clash/Mihomo 路径" "Clash/Mihomo path" "Clash/Mihomo путь")" "$PANEL_DOMAIN" "$CLASH_URI_PATH"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        print_web_domain_http_status "$(localized_text "网站域名" "website domain" "доменное имя сайта")" "$domain" "/"
    done
    print_443_health_status_code_hints

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}路由摘要${PLAIN}" "${BOLD}Route Summary${PLAIN}" "${BOLD}Сводка маршрута${PLAIN}")"
    echo -e "$(localized_text "default_backend 当前指向：${xray_backend}" "default_backend currently points to: ${xray_backend}" "default_backend в настоящее время указывает на: ${xray_backend}")"
    echo -e "$(localized_text "routes 数量：${route_count}" "routes quantity: ${route_count}" "количество маршрутов: ${route_count}")"
    echo -e "$(localized_text "unknown SNI 策略：default_backend -> ${xray_backend}" "unknown SNI policy: default_backend -> ${xray_backend}" "неизвестная политика SNI: default_backend -> ${xray_backend}")"
    ranges=$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")
    echo -e "$(localized_text "web panel: ${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${web_label} ${web_backend} -> 面板后端 ${panel_backend}" "web panel: ${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${web_label} ${web_backend} -> panel backend ${panel_backend}" "веб-панель: ${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${web_label} ${web_backend} -> бэкенд панели ${panel_backend}")"
    echo -e "$(localized_text "web subscription: ${PANEL_DOMAIN}${SUB_URI_PATH} -> ${web_label} ${web_backend} -> 订阅后端 ${sub_backend}" "web subscription: ${PANEL_DOMAIN}${SUB_URI_PATH} -> ${web_label} ${web_backend} -> Subscription backend ${sub_backend}" "веб-подписка: ${PANEL_DOMAIN}${SUB_URI_PATH} -> ${web_label} ${web_backend} -> Сервер подписки ${sub_backend}")"
    echo -e "$(localized_text "web clash/mihomo: ${PANEL_DOMAIN}${CLASH_URI_PATH} -> ${web_label} ${web_backend} -> 订阅后端 ${sub_backend}" "web clash/mihomo: ${PANEL_DOMAIN}${CLASH_URI_PATH} -> ${web_label} ${web_backend} -> Subscription backend ${sub_backend}" "веб-clash/mihomo: ${PANEL_DOMAIN}${CLASH_URI_PATH} -> ${web_label} ${web_backend} -> Сервер подписки ${sub_backend}")"
    echo -e "route panel: ${PANEL_DOMAIN} -> ${web_backend} whitelist=$([[ -n "$ranges" ]] && echo yes || echo no)"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        site_backend=$(format_hostport "${SITE_BACKEND_ADDRS[$i]}" "${SITE_BACKEND_PORTS[$i]}")
        echo -e "$(localized_text "web site: ${domain}/ -> ${web_label} ${web_backend} -> 网站后端 ${site_backend}" "web site: ${domain}/ -> ${web_label} ${web_backend} -> website backend ${site_backend}" "веб-сайт: ${domain}/ -> ${web_label} ${web_backend} -> бэкенд сайта ${site_backend}")"
        echo -e "route site: ${domain} -> ${web_backend} whitelist=$([[ -n "$ranges" ]] && echo yes || echo no)"
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        echo -e "$(localized_text "route tcp: ${domain} -> $(format_hostport "${TCP_ROUTE_ADDRS[$i]}" "${TCP_ROUTE_PORTS[$i]}") whitelist=no（非 Web 域名不启用白名单）" "route tcp: ${domain} -> $(format_hostport \"${TCP_ROUTE_ADDRS[$i]}\" \"${TCP_ROUTE_PORTS[$i]}\") whitelist=no (whitelist is not enabled for non-Web domains)" "маршрут tcp: ${domain} -> $(format_hostport \"${TCP_ROUTE_ADDRS[$i]}\" \"${TCP_ROUTE_PORTS[$i]}\") белый список = нет (белый список не включен для имен доменов, не принадлежащих Интернету)")"
    done
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        echo -e "route xray: ${domain} -> $(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}") whitelist=no"
    done
    echo -e "route reality: ${REALITY_SNI} -> ${xray_backend} whitelist=no"
    print_443_health_reality_notes

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "最近 20 行 vpso-mux 日志：" "The last 20 lines of vpso-mux logs:" "Последние 20 строк логов vpso-mux:")"
    journalctl -u vpso-mux -n 20 --no-pager 2>/dev/null || echo "$(localized_text "未读取到 vpso-mux 日志。" "The vpso-mux log was not read." "Журнал vpso-mux не был прочитан.")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "测试命令：" "Test command:" "Тестовая команда:")"
    echo -e "  openssl s_client -connect SERVER_IP:${NGINX_LISTEN_PORT} -servername ${PANEL_DOMAIN}"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  openssl s_client -connect SERVER_IP:${NGINX_LISTEN_PORT} -servername ${SITE_DOMAINS[0]}"
    echo -e "  openssl s_client -connect SERVER_IP:${NGINX_LISTEN_PORT} -servername random.example.com"
}

check_sni_stack_subscription_hint() {
    local web_label

    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔎 订阅链接与 Hosts / External Proxy 检查提示${PLAIN}" "${BOLD}🔎 Subscription link and Hosts / External Proxy check prompt${PLAIN}" "${BOLD}🔎 Ссылка на подписку и приглашение для проверки хостов/внешнего прокси${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    web_label=$(web_proxy_engine_label)
    echo -e "$(localized_text "3x-ui v3.4.0 及之后：打开 Hosts / 主机，新增 Host：" "3x-ui v3.4.0 and later: Open Hosts / Host and add a Host:" "3x-ui v3.4.0 и новее: откройте Hosts / Хост и добавьте хост:")"
    echo -e "$(localized_text "  入站：选择对应的 REALITY 或本地 Xray 入站" "Inbound: Select the corresponding REALITY or local Xray for inbound" "Входящий: выберите соответствующий REALITY или локальный Xray для входящего подключения.")"
    echo -e "$(localized_text "  地址：你的节点域名或服务器 IP" "Address: your node domain or server IP" "Адрес: доменное имя вашего узла или IP-адрес сервера.")"
    echo -e "$(localized_text "  端口：${NGINX_LISTEN_PORT}" "Port: ${NGINX_LISTEN_PORT}" "Порт: ${NGINX_LISTEN_PORT}")"
    echo -e "$(localized_text "  Security/SNI/Fingerprint/ALPN：按该入站和客户端实际值保持一致" "Security/SNI/Fingerprint/ALPN: The inbound and client actual values are consistent" "Security/SNI/Fingerprint/ALPN: фактические значения входящего и клиентского трафика совпадают.")"
    echo -e ""
    echo -e "$(localized_text "3x-ui v3.3.1 及之前：在 REALITY 入站里开启 External Proxy，并确保：" "3x-ui v3.3.1 and before: Enable External Proxy in REALITY inbound, and make sure:" "3x-ui v3.3.1 и более ранние версии: включите внешний прокси во входящем REALITY и убедитесь:")"
    echo -e "$(localized_text "  类型：相同" "Type: same" "Тип: тот же")"
    echo -e "$(localized_text "  地址：你的节点域名或服务器 IP" "Address: your node domain or server IP" "Адрес: доменное имя вашего узла или IP-адрес сервера.")"
    echo -e "$(localized_text "  端口：${NGINX_LISTEN_PORT}" "Port: ${NGINX_LISTEN_PORT}" "Порт: ${NGINX_LISTEN_PORT}")"
    echo -e "$(localized_text "${YELLOW}提示：本教程推荐 Cloudflare 灰云 / DNS only。REALITY 节点地址必须直连 VPS，可填灰云节点域名或服务器公网 IP。${PLAIN}" "${YELLOW}Tip: This tutorial recommends Cloudflare Gray Cloud / DNS only. REALITY The node address must be directly connected to the VPS. You can fill in the gray cloud node domain or server public IP.${PLAIN}" "${YELLOW}Совет. В этом руководстве рекомендуется использовать только Cloudflare Grey Cloud / DNS. REALITY Адрес узла должен быть напрямую подключен к VPS. Вы можете указать доменное имя серого облачного узла или IP-адрес сервера в Интернете.${PLAIN}")"
    echo -e ""
    echo -e "$(localized_text "复制节点链接后应该看到：" "After copying the node link you should see:" "После копирования ссылки на узел вы должны увидеть:")"
    echo -e "$(localized_text "  vless://...@节点地址:${NGINX_LISTEN_PORT}?security=reality&sni=${REALITY_SNI}&..." "vless://...@Node address:${NGINX_LISTEN_PORT}?security=reality&sni=${REALITY_SNI}&..." "vless://...@Адрес узла: ${NGINX_LISTEN_PORT}?security=reality&sni=${REALITY_SNI}&...")"
    echo -e ""
    echo -e "$(localized_text "订阅公网入口应为：" "The public entry for subscribing should be:" "Вход в публичную сеть для подписки должен быть:")"
    echo -e "$(localized_text "  普通订阅：      https://${PANEL_DOMAIN}${SUB_URI_PATH}" "Ordinary subscription: https://${PANEL_DOMAIN}${SUB_URI_PATH}" "Обычная подписка: https://${PANEL_DOMAIN}${SUB_URI_PATH}.")"
    echo -e "  Clash/Mihomo：  https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    echo -e "$(localized_text "${YELLOW}不要把公网订阅地址写成 :${SUB_LISTEN_PORT}；该端口只给当前本地 Web 反代引擎（${web_label}）访问，不应写成公网订阅入口。${PLAIN}" "${YELLOW}Do not write the public subscription address as: ${SUB_LISTEN_PORT}; this port is only accessible to the current local Web reverse proxy engine (${web_label}) and should not be written as the public subscription entry.${PLAIN}" "${YELLOW}Не записывайте адрес подписки в публичной сети как: ${SUB_LISTEN_PORT}; этот порт доступен только текущему локальному механизму защиты от создания веб-страниц (${web_label}) и не должен записываться как вход для подписки в публичной сети.${PLAIN}")"
    echo -e ""
    echo -e "$(localized_text "${YELLOW}如果链接里还是 :${XRAY_LISTEN_PORT}，3x-ui v3.4.0+ 请检查 Hosts / 主机；旧版请检查入站 External Proxy。${PLAIN}" "${YELLOW}If the link is still: ${XRAY_LISTEN_PORT}, 3x-ui v3.4.0+, please check Hosts / Host; for older versions, please check the inbound External Proxy.${PLAIN}" "${YELLOW}Если ссылка все еще: ${XRAY_LISTEN_PORT}, 3x-ui v3.4.0+, проверьте Hosts / Host; для более старых версий проверьте входящий внешний прокси.${PLAIN}")"
}
