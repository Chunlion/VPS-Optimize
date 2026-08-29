# shellcheck shell=bash
# Port 443 Reuse collection, installation, rendering, certificates, and runtime apply flows.

collect_sni_stack_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}443端口复用部署向导${PLAIN}" "${BOLD}Port 443 Reuse setup${PLAIN}" "${BOLD}Настройка общего порта 443${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}所选入口模式将独占公网 443；Web 域名、反代引擎、证书和白名单由三种模式共用。${PLAIN}" "${YELLOW}The selected entry mode owns public port 443. Web domains, the reverse proxy, certificates, and allowlists are shared across all modes.${PLAIN}" "${YELLOW}Выбранный режим займёт публичный порт 443. Web-домены, обратный прокси, сертификаты и списки доступа общие для всех режимов.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}本地后端默认只监听 127.0.0.1；每项直接回车即可沿用括号中的默认值。${PLAIN}" "${YELLOW}Local backends listen on 127.0.0.1 by default. Press Enter to keep the value shown in parentheses.${PLAIN}" "${YELLOW}По умолчанию локальные бэкенды слушают 127.0.0.1. Нажмите Enter, чтобы принять значение в скобках.${PLAIN}")"
    echo -e "------------------------------------------------"

    local default_panel_addr="127.0.0.1"
    local default_panel_port="40000"
    local default_panel_path="/panel/"
    local default_sub_addr="127.0.0.1"
    local default_sub_port="2096"
    local default_sub_path="/sub/"
    local default_clash_path="/clash/"
    detect_xui_single_443_defaults
    if [[ -n "${XUI_DETECTED_BIN:-}" || -n "${XUI_DETECTED_DB:-}" ]]; then
        default_panel_addr="${XUI_DETECTED_PANEL_ADDR:-127.0.0.1}"
        default_panel_port="${XUI_DETECTED_WEB_PORT:-40000}"
        default_panel_path="${XUI_DETECTED_WEB_BASE_PATH:-/panel/}"
        default_sub_addr="${XUI_DETECTED_SUB_ADDR:-127.0.0.1}"
        default_sub_port="${XUI_DETECTED_SUB_PORT:-2096}"
        default_sub_path="${XUI_DETECTED_SUB_PATH:-/sub/}"
        default_clash_path="${XUI_DETECTED_SUB_CLASH_PATH:-/clash/}"
    fi
    print_xui_single_443_detected_defaults
    echo -e "------------------------------------------------"

    local panel_domain_input reality_sni_input
    echo -e "$(localized_text "${BOLD}${BLUE}▶ [1/5] 域名与 Web 反代引擎${PLAIN}" "${BOLD}${BLUE}▶ [1/5] Domains and Web reverse proxy${PLAIN}" "${BOLD}${BLUE}▶ [1/5] Домены и Web-прокси${PLAIN}")"
    read_trimmed panel_domain_input "$(localized_text "面板域名（仅域名；示例值 panel.example.com）: " "Panel domain (hostname only; example: panel.example.com): " "Домен панели (только имя; пример: panel.example.com): ")"
    PANEL_DOMAIN="$panel_domain_input"
    local web_engine_choice
    WEB_PROXY_ENGINE="caddy"
    echo -e "$(localized_text "${CYAN}Web 反代引擎：${PLAIN}" "${CYAN}Web reverse proxy:${PLAIN}" "${CYAN}Web-прокси:${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  1. Caddy${PLAIN} ${YELLOW}(默认；兼容现有配置)${PLAIN}" "${GREEN}  1. Caddy${PLAIN} ${YELLOW}(default; compatible with existing setups)${PLAIN}" "${GREEN}  1. Caddy${PLAIN} ${YELLOW}(по умолчанию; совместим с текущей конфигурацией)${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  2. Nginx${PLAIN} ${YELLOW}(仅监听本地 HTTPS 端口)${PLAIN}" "${GREEN}  2. Nginx${PLAIN} ${YELLOW}(listens only on a local HTTPS port)${PLAIN}" "${GREEN}  2. Nginx${PLAIN} ${YELLOW}(слушает только локальный HTTPS-порт)${PLAIN}")"
    read_trimmed web_engine_choice "$(localized_text "选择 Web 反代引擎 [1]: " "Select Web reverse proxy [1]: " "Выберите Web-прокси [1]: ")"
    case "${web_engine_choice:-1}" in
        1) WEB_PROXY_ENGINE="caddy" ;;
        2) WEB_PROXY_ENGINE="nginx" ;;
        *) echo -e "$(localized_text "${RED}❌ 无效的 Web 反代引擎选择。${PLAIN}" "${RED}❌ Invalid web reverse proxy engine selection.${PLAIN}" "${RED}❌ Неверный выбор механизма веб-прокси.${PLAIN}")"; return 1 ;;
    esac
    SITE_DOMAINS=()
    SITE_BACKEND_ADDRS=()
    SITE_BACKEND_PORTS=()
    TCP_ROUTE_SNIS=()
    TCP_ROUTE_ADDRS=()
    TCP_ROUTE_PORTS=()
    SNI_IP_WHITELIST_DOMAINS=()
    SNI_IP_WHITELIST_RANGES=()
    local site_domains_input
    local -a site_domain_raw_inputs=()
    echo -e "$(localized_text "${YELLOW}格式示例：app.example.com,status.example.com。只填域名，不要带 https://、端口或路径。${PLAIN}" "${YELLOW}Example format: app.example.com,status.example.com. Enter hostnames only—no https://, port, or path.${PLAIN}" "${YELLOW}Пример: app.example.com,status.example.com. Указывайте только домены, без https://, порта и пути.${PLAIN}")"
    read_trimmed site_domains_input "$(localized_text "其他 Web 域名（可留空；多个用英文逗号分隔）: " "Additional Web domains (optional; separate with commas): " "Дополнительные Web-домены (необязательно; через запятую): ")"
    split_csv_to_array "$site_domains_input" SITE_DOMAINS
    site_domain_raw_inputs=("${SITE_DOMAINS[@]}")
    echo -e "$(localized_text "${YELLOW}REALITY SNI 必须是你实际选择的外部 HTTPS 站点，优先使用不经过 CDN 的域名；不要填写面板域名或节点域名。${PLAIN}" "${YELLOW}REALITY SNI must be an external HTTPS site you actually selected. Prefer a non-CDN hostname; do not use the panel or node domain.${PLAIN}" "${YELLOW}REALITY SNI должен указывать на выбранный вами внешний HTTPS-сайт. Предпочтителен домен без CDN; не используйте домен панели или узла.${PLAIN}")"
    read_trimmed reality_sni_input "$(localized_text "REALITY 目标 SNI（仅域名）: " "REALITY target SNI (hostname only): " "Целевой SNI REALITY (только домен): ")"
    REALITY_SNI="$reality_sni_input"
    STRICT_SNI_GATE="false"
    if strict_sni_gate_mode_supported "${ENTRY_MODE:-nginx-stream}"; then
        echo -e "$(localized_text "${YELLOW}建议启用 SNI 清洗：只放行已登记的面板、网站、Xray 路由和 REALITY SNI，未知或无 SNI 的连接直接丢弃。${PLAIN}" "${YELLOW}SNI filtering is recommended. It allows only registered panel, site, Xray-route, and REALITY SNIs, and drops connections with an unknown or missing SNI.${PLAIN}" "${YELLOW}Рекомендуется включить фильтрацию SNI. Разрешаются только зарегистрированные SNI панели, сайтов, маршрутов Xray и REALITY; подключения с неизвестным или отсутствующим SNI отклоняются.${PLAIN}")"
        if confirm_default_yes "$(localized_text "启用 SNI 清洗（严格门禁）？(Y/n): " "Enable SNI filtering (strict gate)? (Y/n): " "Включить фильтрацию SNI (строгий контроль)? (Y/n): ")"; then
            STRICT_SNI_GATE="true"
        fi
    fi
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}${BLUE}▶ [2/5] 公网入口${PLAIN}" "${BOLD}${BLUE}▶ [2/5] Public entry${PLAIN}" "${BOLD}${BLUE}▶ [2/5] Публичная точка входа${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}一般保持 0.0.0.0:443；只有明确使用其他公网地址或端口时才修改。${PLAIN}" "${YELLOW}Keep 0.0.0.0:443 unless you intentionally use another public address or port.${PLAIN}" "${YELLOW}Обычно оставляйте 0.0.0.0:443. Меняйте только при использовании другого публичного адреса или порта.${PLAIN}")"
    NGINX_LISTEN_ADDR=$(ask_with_default "$(localized_text "公网入口监听地址" "Public entry listen address" "Адрес публичной точки входа")" "0.0.0.0")
    NGINX_LISTEN_PORT=$(ask_with_default "$(localized_text "公网入口端口" "Public entry port" "Порт публичной точки входа")" "443")

    local advanced_mode
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}${BLUE}▶ [3/5] 本地后端${PLAIN}" "${BOLD}${BLUE}▶ [3/5] Local backends${PLAIN}" "${BOLD}${BLUE}▶ [3/5] Локальные бэкенды${PLAIN}")"
    read_trimmed advanced_mode "$(localized_text "修改本地监听地址？(y/N，默认 N；一般直接回车): " "Change local listen addresses? (y/N, default N; usually press Enter): " "Изменить локальные адреса прослушивания? (y/N, по умолчанию N; обычно нажмите Enter): ")"
    if is_yes "$advanced_mode"; then
        CADDY_LISTEN_ADDR=$(ask_with_default "$(localized_text "$(web_proxy_engine_label "$WEB_PROXY_ENGINE")监听地址" "$(web_proxy_engine_label \"$WEB_PROXY_ENGINE\") listening address" "Адрес прослушивания $(web_proxy_engine_label \"$WEB_PROXY_ENGINE\")")" "127.0.0.1")
        XRAY_LISTEN_ADDR=$(ask_with_default "$(localized_text "Xray REALITY 本地监听地址" "Xray REALITY local listening address" "Xray REALITY локальный адрес прослушивания")" "127.0.0.1")
        PANEL_LISTEN_ADDR=$(ask_with_default "$(localized_text "3x-ui 面板监听地址" "3x-ui panel listening address" "Адрес прослушивания панели 3x-ui")" "$default_panel_addr")
        SUB_LISTEN_ADDR=$(ask_with_default "$(localized_text "3x-ui 订阅服务监听地址" "3x-ui Subscription service listening address" "3x-ui Адрес прослушивания службы подписки")" "$default_sub_addr")
    else
        CADDY_LISTEN_ADDR="127.0.0.1"
        XRAY_LISTEN_ADDR="127.0.0.1"
        PANEL_LISTEN_ADDR="$default_panel_addr"
        SUB_LISTEN_ADDR="$default_sub_addr"
        echo -e "$(localized_text "${GREEN}本地监听地址采用检测值或安全默认值；Web 反代和 Xray 使用 127.0.0.1。${PLAIN}" "${GREEN}Using detected or safe local addresses; the Web proxy and Xray use 127.0.0.1.${PLAIN}" "${GREEN}Используются обнаруженные или безопасные локальные адреса; Web-прокси и Xray работают на 127.0.0.1.${PLAIN}")"
    fi

    echo -e "$(localized_text "${YELLOW}下面均为本机内部端口，不要填写公网 443；3x-ui 面板和订阅端口须与面板当前设置一致。${PLAIN}" "${YELLOW}The following are internal ports. Do not enter public port 443; the 3x-ui panel and subscription ports must match the current panel settings.${PLAIN}" "${YELLOW}Ниже указываются внутренние порты. Не вводите публичный порт 443; порты панели и подписки должны совпадать с настройками 3x-ui.${PLAIN}")"
    CADDY_LISTEN_PORT=$(ask_with_default "$(localized_text "$(web_proxy_engine_label "$WEB_PROXY_ENGINE") 本地 HTTPS 端口" "$(web_proxy_engine_label \"$WEB_PROXY_ENGINE\") local HTTPS port" "Локальный HTTPS-порт $(web_proxy_engine_label \"$WEB_PROXY_ENGINE\")")" "8443")
    XRAY_LISTEN_PORT=$(ask_with_default "$(localized_text "Xray REALITY 本地入站端口" "Xray REALITY local inbound port" "Локальный входной порт Xray REALITY")" "1443")
    PANEL_LISTEN_PORT=$(ask_with_default "$(localized_text "3x-ui 面板后端端口" "3x-ui panel backend port" "Порт бэкенда панели 3x-ui")" "$default_panel_port")
    echo -e "$(localized_text "${YELLOW}路径只填以 / 开头和结尾的前缀，不要填域名、端口或客户端 ID。${PLAIN}" "${YELLOW}Paths must start and end with /. Do not include a domain, port, or client ID.${PLAIN}" "${YELLOW}Пути должны начинаться и заканчиваться символом /. Не указывайте домен, порт или ID клиента.${PLAIN}")"
    PANEL_WEB_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "3x-ui 面板路径（须与 webBasePath 一致）" "3x-ui panel path (must match webBasePath)" "Путь панели 3x-ui (должен совпадать с webBasePath)")" "$default_panel_path")")
    SUB_LISTEN_PORT=$(ask_with_default "$(localized_text "3x-ui 订阅后端端口" "3x-ui subscription backend port" "Порт бэкенда подписки 3x-ui")" "$default_sub_port")
    SUB_URI_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "普通订阅路径（仅路径前缀）" "Standard subscription path (path prefix only)" "Путь обычной подписки (только префикс)")" "$default_sub_path")")
    CLASH_URI_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "Clash/Mihomo 订阅路径（仅路径前缀）" "Clash/Mihomo subscription path (path prefix only)" "Путь подписки Clash/Mihomo (только префикс)")" "$default_clash_path")")
    local panel_whitelist_enabled panel_whitelist_input panel_whitelist_ranges current_client_ip
    local -a panel_whitelist_array=()
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}${BLUE}▶ [4/5] 访问控制与网站后端${PLAIN}" "${BOLD}${BLUE}▶ [4/5] Access control and site backends${PLAIN}" "${BOLD}${BLUE}▶ [4/5] Контроль доступа и бэкенды сайтов${PLAIN}")"
    read_trimmed panel_whitelist_enabled "$(localized_text "限制面板访问 IP？(y/N，默认 N): " "Restrict panel access by IP? (y/N, default N): " "Ограничить доступ к панели по IP? (y/N, по умолчанию N): ")"
    if is_yes "$panel_whitelist_enabled"; then
        if ! web_proxy_engine_supports_web_whitelist "${ENTRY_MODE:-nginx-stream}" "$WEB_PROXY_ENGINE"; then
            echo -e "$(localized_text "${RED}❌ xray-fallback 模式不支持 Web 白名单。${PLAIN}" "${RED}❌ xray-fallback mode does not support web whitelisting.${PLAIN}" "${RED}❌ Резервный режим xray не поддерживает белый список веб-сайтов.${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}如需 Web 白名单，请改用 Nginx Stream 或 TCP Peek。${PLAIN}" "${YELLOW}Use Nginx Stream or TCP Peek if you need a Web allowlist.${PLAIN}" "${YELLOW}Для Web-списка доступа используйте Nginx Stream или TCP Peek.${PLAIN}")"
            return 1
        fi
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "$(localized_text "${YELLOW}当前 SSH 来源 IP：${current_client_ip}。请将它加入允许列表，避免面板被锁定。${PLAIN}" "${YELLOW}Current SSH source IP: ${current_client_ip}. Add it to the allowlist to avoid locking yourself out of the panel.${PLAIN}" "${YELLOW}Текущий IP-адрес SSH: ${current_client_ip}. Добавьте его в список, чтобы не потерять доступ к панели.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}示例值：203.0.113.10,203.0.113.0/24；多个值可用空格或英文逗号分隔。${PLAIN}" "${YELLOW}Example: 203.0.113.10,203.0.113.0/24. Separate multiple values with spaces or commas.${PLAIN}" "${YELLOW}Пример: 203.0.113.10,203.0.113.0/24. Разделяйте значения пробелами или запятыми.${PLAIN}")"
        read_trimmed panel_whitelist_input "$(localized_text "允许访问面板的 IP/CIDR: " "Allowed panel IPs/CIDRs: " "Разрешённые IP/CIDR для панели: ")"
        normalize_ip_whitelist_input "$panel_whitelist_input" panel_whitelist_array || return 1
        append_vps_public_ips_to_whitelist panel_whitelist_array
        panel_whitelist_ranges=$(join_array_by_space "${panel_whitelist_array[@]}")
    fi
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i default_site_port
        default_site_port=3000
        for i in "${!SITE_DOMAINS[@]}"; do
            if [[ -z "${SITE_DOMAINS[$i]}" ]]; then
                continue
            fi
            if is_yes "$advanced_mode"; then
                SITE_BACKEND_ADDRS[$i]=$(ask_with_default "$(localized_text "${SITE_DOMAINS[$i]} 后端监听地址" "${SITE_DOMAINS[$i]} backend listen address" "Адрес бэкенда ${SITE_DOMAINS[$i]}")" "127.0.0.1")
            else
                SITE_BACKEND_ADDRS[$i]="127.0.0.1"
            fi
            SITE_BACKEND_PORTS[$i]=$(ask_with_default "$(localized_text "${SITE_DOMAINS[$i]} 后端端口" "${SITE_DOMAINS[$i]} backend port" "Порт бэкенда ${SITE_DOMAINS[$i]}")" "$default_site_port")
            default_site_port=$((default_site_port + 1))
        done
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}${BLUE}▶ [5/5] 3x-ui 证书与 Cloudflare Token${PLAIN}" "${BOLD}${BLUE}▶ [5/5] 3x-ui certificates and Cloudflare token${PLAIN}" "${BOLD}${BLUE}▶ [5/5] Сертификаты 3x-ui и токен Cloudflare${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}公网证书由 $(web_proxy_engine_label "$WEB_PROXY_ENGINE") 统一托管；3x-ui 面板和订阅后端通过 HTTP 提供服务。${PLAIN}" "${YELLOW}$(web_proxy_engine_label \"$WEB_PROXY_ENGINE\") manages the public certificate. The 3x-ui panel and subscription backends serve HTTP locally.${PLAIN}" "${YELLOW}Публичным сертификатом управляет $(web_proxy_engine_label \"$WEB_PROXY_ENGINE\"); бэкенды панели и подписки 3x-ui локально используют HTTP.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}本地连接：面板 ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}；订阅 ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}。${PLAIN}" "${YELLOW}Local targets: panel ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}; subscription ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}.${PLAIN}" "${YELLOW}Локальные адреса: панель ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}; подписка ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}.${PLAIN}")"
    echo -e "$(localized_text "${CYAN}按当前 3x-ui 情况处理：${PLAIN}" "${CYAN}Choose the instruction that matches your 3x-ui setup:${PLAIN}" "${CYAN}Действуйте в зависимости от установки 3x-ui:${PLAIN}")"
    echo -e "$(localized_text "  3x-ui 3.x 新安装：官方安装器选择 4. Skip SSL，再选择 y，仅绑定 127.0.0.1。" "  New 3x-ui 3.x: select 4. Skip SSL in the official installer, then y to bind only to 127.0.0.1." "  Новая установка 3x-ui 3.x: в официальном установщике выберите 4. Skip SSL, затем y для привязки только к 127.0.0.1.")"
    echo -e "$(localized_text "  3x-ui 2.x、旧配置升级或曾启用 SSL：清空面板和订阅证书路径。" "  3x-ui 2.x, upgraded legacy setup, or SSL used before: clear the panel and subscription certificate paths." "  3x-ui 2.x, обновлённая старая конфигурация или ранее включённый SSL: очистите пути сертификатов панели и подписки.")"
    if confirm_danger \
        "$(localized_text "清空 3x-ui 旧证书路径" "Clear legacy 3x-ui certificate paths" "Очистить старые пути сертификатов 3x-ui")" \
        "$(localized_text "清空 3x-ui 2.x 或旧配置中的面板和订阅证书路径，使本地反代改用 HTTP。" "Clear panel and subscription certificate paths in 3x-ui 2.x or legacy configuration so the local proxy can use HTTP." "Очистить пути сертификатов панели и подписки в 3x-ui 2.x или старой конфигурации, чтобы локальный прокси использовал HTTP.")" \
        "$(localized_text "可在 3x-ui 官方菜单中重新填写原证书路径，或恢复操作前备份。" "Restore the original certificate paths from the official 3x-ui menu or a pre-operation backup." "Верните исходные пути через официальное меню 3x-ui или восстановите резервную копию.")"; then
        if ! clear_xui_cert_settings_for_single_443; then
            confirm_default_no "$(localized_text "是否已经手动清空面板和订阅证书路径？(y/N): " "Have you already cleared the panel and subscription certificate paths manually? (y/N): " "Вы уже вручную очистили пути сертификатов панели и подписки? (y/N): ")" || { echo -e "$(localized_text "${YELLOW}请先在 3x-ui 中清空证书路径，保存并重启面板。${PLAIN}" "${YELLOW}Clear the certificate paths in 3x-ui, save, and restart the panel first.${PLAIN}" "${YELLOW}Сначала очистите пути сертификатов в 3x-ui, сохраните изменения и перезапустите панель.${PLAIN}")"; return 1; }
        fi
    else
        confirm_default_no "$(localized_text "是否已经手动清空面板和订阅证书路径？(y/N): " "Have you already cleared the panel and subscription certificate paths manually? (y/N): " "Вы уже вручную очистили пути сертификатов панели и подписки? (y/N): ")" || { echo -e "$(localized_text "${YELLOW}请先在 3x-ui 中清空证书路径，保存并重启面板。${PLAIN}" "${YELLOW}Clear the certificate paths in 3x-ui, save, and restart the panel first.${PLAIN}" "${YELLOW}Сначала очистите пути сертификатов в 3x-ui, сохраните изменения и перезапустите панель.${PLAIN}")"; return 1; }
    fi

    echo -e "$(localized_text "${CYAN}Cloudflare API Token 权限：Zone - DNS - Edit、Zone - Zone - Read；仅授权实际使用的 Zone。${PLAIN}" "${CYAN}Cloudflare API token permissions: Zone - DNS - Edit and Zone - Zone - Read. Limit it to the zones you use.${PLAIN}" "${CYAN}Права токена Cloudflare API: Zone - DNS - Edit и Zone - Zone - Read. Ограничьте токен используемыми зонами.${PLAIN}")"
    read_secret_trimmed CF_TOKEN "$(localized_text "粘贴 Cloudflare API Token: " "Paste Cloudflare API token: " "Вставьте токен Cloudflare API: ")"

    PANEL_DOMAIN=$(normalize_domain_input "$panel_domain_input")
    REALITY_SNI=$(normalize_domain_input "$reality_sni_input")
    local site_idx
    for site_idx in "${!SITE_DOMAINS[@]}"; do
        SITE_DOMAINS[$site_idx]=$(normalize_domain_input "${SITE_DOMAINS[$site_idx]}")
        SITE_BACKEND_ADDRS[$site_idx]=$(normalize_backend_addr_input "${SITE_BACKEND_ADDRS[$site_idx]:-127.0.0.1}")
    done

    if ! is_valid_domain "$PANEL_DOMAIN"; then print_domain_validation_error "$(localized_text "面板域名" "Panel domain" "Доменное имя панели")" "$panel_domain_input" "$PANEL_DOMAIN"; return 1; fi
    if ! is_valid_domain "$REALITY_SNI"; then print_domain_validation_error "REALITY SNI" "$reality_sni_input" "$REALITY_SNI"; return 1; fi
    check_domain_dns_sanity "$PANEL_DOMAIN" "$(localized_text "面板域名" "Panel domain" "Доменное имя панели")" "prompt" || return 1
    check_domain_dns_sanity "$REALITY_SNI" "REALITY SNI" "prompt" || return 1
    local site_domain seen_domains
    seen_domains=" ${PANEL_DOMAIN} ${REALITY_SNI} "
    for site_idx in "${!SITE_DOMAINS[@]}"; do
        site_domain="${SITE_DOMAINS[$site_idx]}"
        [[ -z "$site_domain" ]] && continue
        if ! is_valid_domain "$site_domain"; then print_domain_validation_error "$(localized_text "网站/反代域名" "Website/reverse domain" "Веб-сайт/обратное доменное имя")" "${site_domain_raw_inputs[$site_idx]:-$site_domain}" "$site_domain"; return 1; fi
        if [[ "$site_domain" == "$PANEL_DOMAIN" || "$site_domain" == "$REALITY_SNI" || "$seen_domains" == *" ${site_domain} "* ]]; then
            echo -e "$(localized_text "${RED}❌ 面板域名、网站/反代域名、REALITY SNI 不能相同：${site_domain}${PLAIN}" "${RED}❌ Panel domain, website/reverse domain, REALITY SNI cannot be the same: ${site_domain}${PLAIN}" "${RED}❌ Доменное имя панели, веб-сайт/обратное доменное имя, REALITY SNI не могут быть одинаковыми: ${site_domain}${PLAIN}")"
            return 1
        fi
        check_domain_dns_sanity "$site_domain" "$(localized_text "网站/反代域名" "Website/reverse domain" "Веб-сайт/обратное доменное имя")" "prompt" || return 1
        seen_domains+=" ${site_domain} "
    done

    local a validation_idx
    local -a port_labels=(
        "$(localized_text "公网入口端口" "Public entry port" "Порт публичной точки входа")"
        "$(localized_text "Web 反代本地 HTTPS 端口" "Web proxy local HTTPS port" "Локальный HTTPS-порт Web-прокси")"
        "$(localized_text "Xray REALITY 本地入站端口" "Xray REALITY local inbound port" "Локальный входной порт Xray REALITY")"
        "$(localized_text "3x-ui 面板后端端口" "3x-ui panel backend port" "Порт бэкенда панели 3x-ui")"
        "$(localized_text "3x-ui 订阅后端端口" "3x-ui subscription backend port" "Порт бэкенда подписки 3x-ui")"
    )
    local -a port_values=("$NGINX_LISTEN_PORT" "$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT")
    for site_idx in "${!SITE_BACKEND_PORTS[@]}"; do
        port_labels+=("$(localized_text "${SITE_DOMAINS[$site_idx]} 后端端口" "${SITE_DOMAINS[$site_idx]} backend port" "Порт бэкенда ${SITE_DOMAINS[$site_idx]}")")
        port_values+=("${SITE_BACKEND_PORTS[$site_idx]}")
    done
    for validation_idx in "${!port_values[@]}"; do
        is_valid_port "${port_values[$validation_idx]}" || {
            echo -e "$(localized_text "${RED}❌ ${port_labels[$validation_idx]}无效：${port_values[$validation_idx]}。请输入 1–65535。${PLAIN}" "${RED}❌ Invalid ${port_labels[$validation_idx]}: ${port_values[$validation_idx]}. Enter a value from 1 to 65535.${PLAIN}" "${RED}❌ Неверное значение «${port_labels[$validation_idx]}»: ${port_values[$validation_idx]}. Введите число от 1 до 65535.${PLAIN}")"
            return 1
        }
    done
    local -a listen_labels=(
        "$(localized_text "公网入口监听地址" "Public entry listen address" "Адрес публичной точки входа")"
        "$(localized_text "Web 反代监听地址" "Web proxy listen address" "Адрес Web-прокси")"
        "$(localized_text "Xray REALITY 监听地址" "Xray REALITY listen address" "Адрес Xray REALITY")"
        "$(localized_text "3x-ui 面板监听地址" "3x-ui panel listen address" "Адрес панели 3x-ui")"
        "$(localized_text "3x-ui 订阅监听地址" "3x-ui subscription listen address" "Адрес подписки 3x-ui")"
    )
    local -a listen_values=("$NGINX_LISTEN_ADDR" "$CADDY_LISTEN_ADDR" "$XRAY_LISTEN_ADDR" "$PANEL_LISTEN_ADDR" "$SUB_LISTEN_ADDR")
    for validation_idx in "${!listen_values[@]}"; do
        is_valid_listen_addr "${listen_values[$validation_idx]}" || {
            echo -e "$(localized_text "${RED}❌ ${listen_labels[$validation_idx]}无效：${listen_values[$validation_idx]}。${PLAIN}" "${RED}❌ Invalid ${listen_labels[$validation_idx]}: ${listen_values[$validation_idx]}.${PLAIN}" "${RED}❌ Неверное значение «${listen_labels[$validation_idx]}»: ${listen_values[$validation_idx]}.${PLAIN}")"
            return 1
        }
    done
    for site_idx in "${!SITE_BACKEND_ADDRS[@]}"; do
        a="${SITE_BACKEND_ADDRS[$site_idx]}"
        is_valid_backend_addr "$a" || { echo -e "$(localized_text "${RED}❌ ${SITE_DOMAINS[$site_idx]} 后端地址无效：${a}${PLAIN}" "${RED}❌ Invalid backend address for ${SITE_DOMAINS[$site_idx]}: ${a}${PLAIN}" "${RED}❌ Неверный адрес бэкенда ${SITE_DOMAINS[$site_idx]}: ${a}.${PLAIN}")"; return 1; }
    done
    is_valid_path_prefix "$PANEL_WEB_PATH" || { echo -e "$(localized_text "${RED}❌ 面板路径无效：${PANEL_WEB_PATH}。路径须以 / 开头和结尾。${PLAIN}" "${RED}❌ Invalid panel path: ${PANEL_WEB_PATH}. It must start and end with /.${PLAIN}" "${RED}❌ Неверный путь панели: ${PANEL_WEB_PATH}. Путь должен начинаться и заканчиваться символом /.${PLAIN}")"; return 1; }
    is_valid_path_prefix "$SUB_URI_PATH" || { echo -e "$(localized_text "${RED}❌ 普通订阅路径无效：${SUB_URI_PATH}。路径须以 / 开头和结尾。${PLAIN}" "${RED}❌ Invalid standard subscription path: ${SUB_URI_PATH}. It must start and end with /.${PLAIN}" "${RED}❌ Неверный путь обычной подписки: ${SUB_URI_PATH}. Путь должен начинаться и заканчиваться символом /.${PLAIN}")"; return 1; }
    is_valid_path_prefix "$CLASH_URI_PATH" || { echo -e "$(localized_text "${RED}❌ Clash/Mihomo 订阅路径无效：${CLASH_URI_PATH}。路径须以 / 开头和结尾。${PLAIN}" "${RED}❌ Invalid Clash/Mihomo subscription path: ${CLASH_URI_PATH}. It must start and end with /.${PLAIN}" "${RED}❌ Неверный путь подписки Clash/Mihomo: ${CLASH_URI_PATH}. Путь должен начинаться и заканчиваться символом /.${PLAIN}")"; return 1; }
    if [[ "$PANEL_WEB_PATH" == "$SUB_URI_PATH" || "$PANEL_WEB_PATH" == "$CLASH_URI_PATH" || "$SUB_URI_PATH" == "$CLASH_URI_PATH" ]]; then
        echo -e "$(localized_text "${RED}❌ 面板路径、普通订阅路径、Clash/Mihomo 路径不能相同。${PLAIN}" "${RED}❌ The panel path, normal subscription path, and Clash/Mihomo path cannot be the same.${PLAIN}" "${RED}❌ Путь к панели, обычный путь подписки и путь Clash/Mihomo не могут совпадать.${PLAIN}")"
        return 1
    fi
    SITE_DOMAIN="${SITE_DOMAINS[0]:-}"
    SITE_BACKEND_ADDR="${SITE_BACKEND_ADDRS[0]:-127.0.0.1}"
    SITE_BACKEND_PORT="${SITE_BACKEND_PORTS[0]:-3000}"
    if [[ -n "${panel_whitelist_ranges:-}" ]]; then
        set_sni_ip_whitelist_for_domain "$PANEL_DOMAIN" "$panel_whitelist_ranges"
    fi
    [[ "$NGINX_LISTEN_PORT" != "443" ]] && echo -e "$(localized_text "${YELLOW}⚠️ 公网入口端口不是 443，客户端和订阅链接必须显式填写端口。${PLAIN}" "${YELLOW}⚠️ The public entry is not port 443. Clients and subscription links must include the port explicitly.${PLAIN}" "${YELLOW}⚠️ Публичная точка входа использует не порт 443. Укажите порт в клиентах и ссылках подписки.${PLAIN}")"

    warn_if_public_bind "$(web_proxy_engine_label "$WEB_PROXY_ENGINE")" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    warn_if_public_bind "$(localized_text "3x-ui 面板" "3x-ui panel" "Панель 3x-ui")" "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT" || return 1
    warn_if_public_bind "$(localized_text "3x-ui 订阅服务" "3x-ui Subscription Service" "Служба подписки 3x-ui")" "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT" || return 1
    for site_idx in "${!SITE_DOMAINS[@]}"; do
        [[ -n "${SITE_DOMAINS[$site_idx]}" ]] || continue
        confirm_backend_target_or_continue "$(localized_text "网站/反代后端 ${SITE_DOMAINS[$site_idx]}" "Website/reverse proxy backend ${SITE_DOMAINS[$site_idx]}" "Сайт/бэкенд обратного прокси ${SITE_DOMAINS[$site_idx]}")" "${SITE_BACKEND_ADDRS[$site_idx]}" "${SITE_BACKEND_PORTS[$site_idx]}" || return 1
    done

    if [[ -z "$CF_TOKEN" || ${#CF_TOKEN} -lt 20 ]]; then echo -e "$(localized_text "${RED}❌ Cloudflare API Token 为空或不完整。请粘贴 API Token，不要填写 Global API Key、邮箱或 Zone ID。${PLAIN}" "${RED}❌ The Cloudflare API token is empty or incomplete. Paste the API token, not a Global API Key, email address, or Zone ID.${PLAIN}" "${RED}❌ Токен Cloudflare API пуст или неполный. Вставьте API Token, а не Global API Key, email или Zone ID.${PLAIN}")"; return 1; fi
    echo -e "$(localized_text "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}" "${CYAN}▶ Verifying online Cloudflare Token...${PLAIN}" "${CYAN}▶ Проверка токена Cloudflare онлайн...${PLAIN}")"
    verify_cf_token_online "$CF_TOKEN"
    local verify_rc=$?
    if [[ "$verify_rc" -eq 0 ]]; then
        echo -e "$(localized_text "${GREEN}✅ Cloudflare Token 校验通过。${PLAIN}" "${GREEN}✅ Cloudflare Token verification passed.${PLAIN}" "${GREEN}✅ Cloudflare Проверка токена пройдена.${PLAIN}")"
    elif [[ "$verify_rc" -eq 2 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未安装 curl，已跳过在线校验。${PLAIN}" "${YELLOW}⚠️ curl is not installed; online verification was skipped.${PLAIN}" "${YELLOW}⚠️ curl не установлен; онлайн-проверка пропущена.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ Cloudflare API Token 校验失败。请检查 Token 权限、授权 Zone 和 IP 限制。${PLAIN}" "${RED}❌ Cloudflare API token verification failed. Check its permissions, authorized zones, and IP restrictions.${PLAIN}" "${RED}❌ Проверка токена Cloudflare API не пройдена. Проверьте права, разрешённые зоны и ограничения по IP.${PLAIN}")"
        return 1
    fi
}

install_caddy_if_needed() {
    command -v caddy >/dev/null 2>&1 && return 0
    echo -e "$(localized_text "${CYAN}▶ 未检测到 Caddy，正在安装...${PLAIN}" "${CYAN}▶ Caddy not detected, installing...${PLAIN}" "${CYAN}▶ Caddy не обнаружен, устанавливается...${PLAIN}")"
    if is_debian; then
        local key_tmp repo_tmp
        install_pkg debian-keyring debian-archive-keyring apt-transport-https curl gpg || return 1
        command -v curl >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 缺少 curl，无法添加 Caddy 源。${PLAIN}" "${RED}❌ curl is missing and the Caddy source cannot be added.${PLAIN}" "${RED}❌ curl отсутствует, и источник Caddy не может быть добавлен.${PLAIN}")"; return 1; }
        command -v gpg >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 缺少 gpg，无法校验 Caddy 源。${PLAIN}" "${RED}❌ Missing gpg, unable to verify Caddy source.${PLAIN}" "${RED}❌ Отсутствует gpg, невозможно проверить источник Caddy.${PLAIN}")"; return 1; }
        key_tmp=$(mktemp /tmp/caddy-key.XXXXXX) || return 1
        repo_tmp=$(mktemp /tmp/caddy-repo.XXXXXX) || { rm -f "$key_tmp"; return 1; }
        if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' -o "$key_tmp"; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "$(localized_text "${RED}❌ Caddy GPG key 下载失败。${PLAIN}" "${RED}❌ Caddy GPG key download failed.${PLAIN}" "${RED}❌ Caddy Загрузка ключа GPG не удалась.${PLAIN}")"
            return 1
        fi
        if ! gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg "$key_tmp"; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "$(localized_text "${RED}❌ Caddy GPG key 写入失败。${PLAIN}" "${RED}❌ Caddy GPG key writing failed.${PLAIN}" "${RED}❌ Caddy Не удалось записать ключ GPG.${PLAIN}")"
            return 1
        fi
        if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' -o "$repo_tmp"; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "$(localized_text "${RED}❌ Caddy APT 源配置下载失败。${PLAIN}" "${RED}❌ Caddy APT source configuration download failed.${PLAIN}" "${RED}❌ Caddy Не удалось загрузить исходную конфигурацию APT.${PLAIN}")"
            return 1
        fi
        if ! mv "$repo_tmp" /etc/apt/sources.list.d/caddy-stable.list; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "$(localized_text "${RED}❌ Caddy APT 源配置写入失败。${PLAIN}" "${RED}❌ Caddy APT source configuration failed to write.${PLAIN}" "${RED}❌ Caddy Не удалось записать исходную конфигурацию APT.${PLAIN}")"
            return 1
        fi
        rm -f "$key_tmp"
        install_pkg caddy || return 1
    elif is_redhat; then
        install_pkg yum-utils || true
        if command -v yum-config-manager >/dev/null 2>&1; then
            yum-config-manager --add-repo https://openrepo.io/repo/caddy/caddy.repo >/dev/null 2>&1 || return 1
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 yum-config-manager，将尝试直接从系统源安装 Caddy。${PLAIN}" "${YELLOW}⚠️ yum-config-manager not detected, will try to install Caddy directly from system sources.${PLAIN}" "${YELLOW}⚠️ yum-config-manager не обнаружен, попытается установить Caddy непосредственно из системных источников.${PLAIN}")"
        fi
        install_pkg caddy || return 1
    else
        echo -e "$(localized_text "${RED}❌ 暂不支持当前系统自动安装 Caddy。${PLAIN}" "${RED}❌ The current system does not support automatic installation of Caddy.${PLAIN}" "${RED}❌ Текущая система не поддерживает автоматическую установку Caddy.${PLAIN}")"
        return 1
    fi
    command -v caddy >/dev/null 2>&1
}

ensure_caddy_module_layout() {
    mkdir -p /etc/caddy/conf.d || return 1
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        cat <<'EOF' > /etc/caddy/Caddyfile
import conf.d/*
EOF
        return 0
    fi
    if ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
        cp -p /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)" 2>/dev/null || true
        printf '\nimport conf.d/*\n' >> /etc/caddy/Caddyfile
    fi
}

install_nginx_stream_stack() {
    echo -e "$(localized_text "${CYAN}▶ 正在检查 Nginx stream 组件...${PLAIN}" "${CYAN}▶ Checking Nginx stream assembly...${PLAIN}" "${CYAN}▶ Проверка сборки Nginx stream...${PLAIN}")"
    local need_install=0
    local nginx_build
    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 Nginx，正在安装基础组件...${PLAIN}" "${YELLOW}⚠️ Nginx not detected, installing basic components...${PLAIN}" "${YELLOW}⚠️ Nginx не обнаружен, установка основных компонентов...${PLAIN}")"
        need_install=1
    else
        nginx_build=$(nginx -V 2>&1 || true)
    fi

    if [[ "$need_install" -eq 0 ]]; then
        if [[ "$nginx_build" == *"--with-stream=dynamic"* ]]; then
            if grep -Rqs 'load_module .*ngx_stream_module\.so' /etc/nginx/nginx.conf /etc/nginx/modules-enabled 2>/dev/null; then
                echo -e "$(localized_text "${GREEN}✅ 已检测到 Nginx stream 动态模块加载配置，跳过安装步骤。${PLAIN}" "${GREEN}✅ The Nginx stream dynamic module loading configuration has been detected, skipping the installation step.${PLAIN}" "${GREEN}✅ Обнаружена конфигурация динамической загрузки модуля Nginx stream, этап установки пропущен.${PLAIN}")"
            else
                echo -e "$(localized_text "${YELLOW}⚠️ Nginx 支持动态 stream 模块，但未确认模块已加载，正在尝试补齐模块...${PLAIN}" "${YELLOW}⚠️ Nginx supports dynamic stream module, but the module has not been confirmed to be loaded. Trying to complete the module...${PLAIN}" "${YELLOW}⚠️ Nginx поддерживает модуль динамического потока, но загрузка модуля не подтверждена. Пытаюсь завершить модуль...${PLAIN}")"
                need_install=1
            fi
        elif [[ "$nginx_build" == *"--with-stream"* || "$nginx_build" == *"--with-stream_ssl_preread_module"* ]]; then
            echo -e "$(localized_text "${GREEN}✅ 已检测到 Nginx stream 静态支持，跳过安装步骤。${PLAIN}" "${GREEN}✅ Static support for Nginx stream has been detected, skipping the installation step.${PLAIN}" "${GREEN}✅ Обнаружена статическая поддержка Nginx stream, пропуская этап установки.${PLAIN}")"
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 未确认 Nginx stream 支持，正在尝试补齐模块...${PLAIN}" "${YELLOW}⚠️ Unconfirmed Nginx stream support, trying to complete the module...${PLAIN}" "${YELLOW}⚠️ Неподтвержденная поддержка Nginx stream, пытаюсь завершить модуль...${PLAIN}")"
            need_install=1
        fi
    fi

    if [[ "$need_install" -eq 1 ]]; then
        if is_debian; then
            install_pkg nginx libnginx-mod-stream
        elif is_redhat; then
            install_pkg nginx
            install_pkg nginx-mod-stream || echo -e "$(localized_text "${YELLOW}⚠️ nginx-mod-stream 安装失败或仓库未提供，将继续检测 Nginx stream 支持。${PLAIN}" "${YELLOW}⚠️ If the installation of nginx-mod-stream fails or the warehouse does not provide it, Nginx stream support will continue to be detected.${PLAIN}" "${YELLOW}⚠️ Если установка nginx-mod-stream не удалась или склад не предоставляет его, поддержка Nginx stream продолжит обнаруживаться.${PLAIN}")"
        fi
    fi
    command -v nginx >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ Nginx 安装失败。${PLAIN}" "${RED}❌ Nginx installation failed.${PLAIN}" "${RED}❌ Установка Nginx не удалась.${PLAIN}")"; return 1; }
    mkdir -p /etc/nginx/stream.d
    if ! grep -Eq '^[[:space:]]*stream[[:space:]]*\{' /etc/nginx/nginx.conf 2>/dev/null; then
        cp -f /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak_$(date +%s)" 2>/dev/null || true
        cat <<'EOF' >> /etc/nginx/nginx.conf

stream {
    include /etc/nginx/stream.d/*.conf;
}
EOF
    elif ! grep -q '/etc/nginx/stream.d/\*.conf' /etc/nginx/nginx.conf 2>/dev/null; then
        cp -f /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak_$(date +%s)" 2>/dev/null || true
        sed -i '/^[[:space:]]*stream[[:space:]]*{/a\    include /etc/nginx/stream.d/*.conf;' /etc/nginx/nginx.conf
    fi
}

harden_nginx_public_errors() {
    local nginx_conf="/etc/nginx/nginx.conf"
    local drop_conf="/etc/nginx/conf.d/00-vps-default-drop.conf"
    local quarantine_dir="/etc/vps-optimize/nginx-default-sites-disabled_$(date +%s)"
    local moved=0
    local default_file

    command -v nginx >/dev/null 2>&1 || return 0
    mkdir -p /etc/nginx/conf.d /etc/vps-optimize

    if [[ -f "$nginx_conf" ]]; then
        if grep -Eq '^[#[:space:]]*server_tokens[[:space:]]+' "$nginx_conf"; then
            sed -i 's/^[#[:space:]]*server_tokens[[:space:]].*;/    server_tokens off;/' "$nginx_conf"
        elif grep -Eq '^[[:space:]]*http[[:space:]]*\{' "$nginx_conf"; then
            sed -i '/^[[:space:]]*http[[:space:]]*{/a\    server_tokens off;' "$nginx_conf"
        fi
    fi

    for default_file in \
        /etc/nginx/sites-enabled/default \
        /etc/nginx/sites-available/default \
        /etc/nginx/conf.d/default.conf; do
        if [[ -e "$default_file" ]]; then
            mkdir -p "$quarantine_dir"
            mv "$default_file" "$quarantine_dir/" >/dev/null 2>&1 && ((moved++))
        fi
    done

    cat <<'EOF' > "$drop_conf"
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}
EOF

    if [[ "$moved" -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 已隔离 ${moved} 个 Nginx 默认站点配置到：${quarantine_dir}${PLAIN}" "${YELLOW}⚠️ Isolated ${moved} Nginx The default site is configured to: ${quarantine_dir}${PLAIN}" "${YELLOW}⚠️ Изолированный ${moved} Nginx Сайт по умолчанию настроен на: ${quarantine_dir}${PLAIN}")"
    fi
    echo -e "$(localized_text "${GREEN}✅ 已关闭 Nginx 版本号显示，并写入 80 端口默认丢弃规则。${PLAIN}" "${GREEN}✅ The Nginx version number display has been turned off, and the default discard rule of port 80 has been written.${PLAIN}" "${GREEN}. Отображение номера версии Nginx отключено и записано правило отбрасывания по умолчанию для порта 80.${PLAIN}")"
}

write_nginx_sni_stream_config() {
    local conf_file="${1:-/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf}"
    local validate="${2:-yes}"
    local listen_directives
    local web_backend
    local xray_backend
    local guarded_backend_var="\$vps_sni_backend"
    local default_backend_name="xray_backend"
    local reject_backend_required="false"
    local -a whitelist_block_vars=()
    listen_directives=$(nginx_stream_listen_directives "$NGINX_LISTEN_ADDR" "$NGINX_LISTEN_PORT")
    web_backend=$(web_proxy_backend)
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    if strict_sni_gate_enabled; then
        validate_strict_sni_gate_reality_server_names || return 1
        default_backend_name="vps_ip_reject_backend"
        reject_backend_required="true"
    fi

    : > "$conf_file"
    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -gt 0 ]]; then
        local i domain ranges suffix allow_var block_var range
        for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
            domain="${SNI_IP_WHITELIST_DOMAINS[$i]}"
            ranges="${SNI_IP_WHITELIST_RANGES[$i]}"
            [[ -n "$domain" && -n "$ranges" ]] || continue
            is_sni_stack_web_domain "$domain" || continue
            suffix=$(nginx_var_suffix_for_domain "$domain")
            allow_var="vps_ip_allow_${suffix}"
            block_var="vps_ip_block_${suffix}"
            whitelist_block_vars+=("\$${block_var}")
            cat <<EOF >> "$conf_file"
geo \$${allow_var} {
    default 0;
EOF
            for range in $ranges; do
                echo "    ${range} 1;" >> "$conf_file"
            done
            cat <<EOF >> "$conf_file"
}

map "\$ssl_preread_server_name:\$${allow_var}" \$${block_var} {
    default 0;
    "${domain}:0" 1;
}

EOF
        done
    fi

    cat <<EOF >> "$conf_file"
map \$ssl_preread_server_name \$vps_sni_backend {
    ${PANEL_DOMAIN} web_proxy_backend;
EOF
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local site_domain
        for site_domain in "${SITE_DOMAINS[@]}"; do
            [[ -n "$site_domain" ]] && echo "    ${site_domain} web_proxy_backend;" >> "$conf_file"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i tcp_sni
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            tcp_sni="${TCP_ROUTE_SNIS[$tcp_i]}"
            [[ -n "$tcp_sni" ]] && echo "    ${tcp_sni} vps_tcp_route_${tcp_i}_backend;" >> "$conf_file"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i xray_route_sni
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            xray_route_sni="${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}"
            [[ -n "$xray_route_sni" ]] && echo "    ${xray_route_sni} vps_xray_route_${xray_route_i}_backend;" >> "$conf_file"
        done
    fi
    cat <<EOF >> "$conf_file"
    ${REALITY_SNI} xray_backend;
    default ${default_backend_name};
}

EOF
    if [[ ${#whitelist_block_vars[@]} -gt 0 ]]; then
        reject_backend_required="true"
        local whitelist_key
        whitelist_key=$(printf '%s' "${whitelist_block_vars[@]}")
        guarded_backend_var="\$vps_sni_guarded_backend"
        cat <<EOF >> "$conf_file"
map "${whitelist_key}" \$vps_sni_ip_blocked {
    default 0;
    ~1 1;
}

map \$vps_sni_ip_blocked \$vps_sni_guarded_backend {
    1 vps_ip_reject_backend;
    default \$vps_sni_backend;
}

EOF
    fi

    cat <<EOF >> "$conf_file"

upstream web_proxy_backend {
    server ${web_backend};
}

upstream xray_backend {
    server ${xray_backend};
}

EOF
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i tcp_sni tcp_backend
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            tcp_sni="${TCP_ROUTE_SNIS[$tcp_i]}"
            [[ -n "$tcp_sni" ]] || continue
            tcp_backend=$(format_hostport "${TCP_ROUTE_ADDRS[$tcp_i]}" "${TCP_ROUTE_PORTS[$tcp_i]}")
            cat <<EOF >> "$conf_file"
upstream vps_tcp_route_${tcp_i}_backend {
    server ${tcp_backend};
}

EOF
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i xray_route_sni xray_route_backend
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            xray_route_sni="${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}"
            [[ -n "$xray_route_sni" ]] || continue
            xray_route_backend=$(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}" "${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}")
            cat <<EOF >> "$conf_file"
upstream vps_xray_route_${xray_route_i}_backend {
    server ${xray_route_backend};
}

EOF
        done
    fi
    if [[ "$reject_backend_required" == "true" ]]; then
        cat <<'EOF' >> "$conf_file"
upstream vps_ip_reject_backend {
    server unix:/dev/null;
}

EOF
    fi

    cat <<EOF >> "$conf_file"
server {
${listen_directives}
    ssl_preread on;
    proxy_pass ${guarded_backend_var};
    proxy_connect_timeout 10s;
    proxy_timeout 24h;
}
EOF
    if [[ "$validate" == "yes" ]]; then
        nginx -t
    fi
}

ensure_caddy_local_base_config() {
    install_caddy_if_needed || return 1
    mkdir -p /etc/caddy/conf.d /etc/caddy/certs
    cp -f /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)" 2>/dev/null || true
    cat <<'EOF' > /etc/caddy/Caddyfile
{
    auto_https off
}

import conf.d/*
EOF
}

write_caddy_panel_config() {
    local output_file="${1:-/etc/caddy/conf.d/${PANEL_DOMAIN}.caddy}"
    local panel_backend
    local sub_backend
    local sub_match_paths
    panel_backend=$(format_hostport "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT")
    sub_backend=$(format_hostport "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT")
    SUB_URI_PATH=$(normalize_path_prefix "${SUB_URI_PATH:-/sub/}")
    CLASH_URI_PATH=$(normalize_path_prefix "${CLASH_URI_PATH:-/clash/}")
    sub_match_paths=$(caddy_path_match_tokens "$SUB_URI_PATH" "$CLASH_URI_PATH")
    cat <<EOF > "$output_file"
https://${PANEL_DOMAIN}:${CADDY_LISTEN_PORT} {
    bind ${CADDY_LISTEN_ADDR}
    tls /etc/caddy/certs/${PANEL_DOMAIN}.crt /etc/caddy/certs/${PANEL_DOMAIN}.key
    encode gzip

    @sub path ${sub_match_paths}
    handle @sub {
        reverse_proxy ${sub_backend} {
            header_up Host {http.request.host}
            header_up X-Forwarded-Proto https
            header_up X-Forwarded-Port ${NGINX_LISTEN_PORT}
            header_up X-Real-IP {remote_host}
            header_up Range {http.request.header.Range}
            header_up If-Range {http.request.header.If-Range}
        }
    }

    handle {
        reverse_proxy ${panel_backend} {
            header_up Host {http.request.host}
            header_up X-Forwarded-Proto https
            header_up X-Forwarded-Port ${NGINX_LISTEN_PORT}
            header_up X-Real-IP {remote_host}
            header_up Range {http.request.header.Range}
            header_up If-Range {http.request.header.If-Range}
        }
    }
}
EOF
}

write_caddy_site_config() {
    [[ ${#SITE_DOMAINS[@]} -eq 0 ]] && return 0
    local output_dir="${1:-/etc/caddy/conf.d}"
    local i site_domain site_backend
    for i in "${!SITE_DOMAINS[@]}"; do
        site_domain="${SITE_DOMAINS[$i]}"
        [[ -z "$site_domain" ]] && continue
        site_backend=$(format_hostport "${SITE_BACKEND_ADDRS[$i]}" "${SITE_BACKEND_PORTS[$i]}")
        cat <<EOF > "${output_dir}/${site_domain}.caddy"
https://${site_domain}:${CADDY_LISTEN_PORT} {
    bind ${CADDY_LISTEN_ADDR}
    tls /etc/caddy/certs/${site_domain}.crt /etc/caddy/certs/${site_domain}.key
    encode gzip

    reverse_proxy ${site_backend} {
        header_up Host {http.request.host}
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Port ${NGINX_LISTEN_PORT}
        header_up X-Real-IP {remote_host}
    }
}
EOF
    done
}

nginx_single_443_web_conf_path() {
    echo "/etc/nginx/conf.d/vps_sni_web_${CADDY_LISTEN_PORT}.conf"
}

nginx_http_listen_directive() {
    local addr="$1"
    local port="$2"
    if [[ "$addr" == *:* && "$addr" != \[*\] ]]; then
        printf '    listen [%s]:%s ssl http2;\n' "$addr" "$port"
    else
        printf '    listen %s:%s ssl http2;\n' "$addr" "$port"
    fi
}

write_nginx_single_443_proxy_headers() {
    cat <<EOF
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Port ${NGINX_LISTEN_PORT};
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$vps_proxy_connection_upgrade;
        proxy_set_header Range \$http_range;
        proxy_set_header If-Range \$http_if_range;
EOF
}

append_nginx_single_443_path_proxy() {
    local output_file="$1"
    local path_prefix="$2"
    local backend="$3"
    local exact_path
    path_prefix=$(normalize_path_prefix "$path_prefix")
    exact_path="${path_prefix%/}"
    cat <<EOF >> "$output_file"

    location = ${exact_path} {
        return 308 ${path_prefix};
    }

    location ^~ ${path_prefix} {
EOF
    write_nginx_single_443_proxy_headers >> "$output_file"
    cat <<EOF >> "$output_file"
        proxy_pass http://${backend};
    }
EOF
}

write_nginx_single_443_web_config() {
    local conf_file="${1:-$(nginx_single_443_web_conf_path)}"
    local panel_backend sub_backend site_backend i site_domain
    panel_backend=$(format_hostport "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT")
    sub_backend=$(format_hostport "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT")
    SUB_URI_PATH=$(normalize_path_prefix "${SUB_URI_PATH:-/sub/}")
    CLASH_URI_PATH=$(normalize_path_prefix "${CLASH_URI_PATH:-/clash/}")
    mkdir -p "$(dirname "$conf_file")" || return 1

    cat <<EOF > "$conf_file"
# Managed by VPS-Optimize Port 443 Reuse. Local HTTPS Web proxy only.
server {
$(nginx_http_listen_directive "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    server_name ${PANEL_DOMAIN};

    ssl_certificate /etc/caddy/certs/${PANEL_DOMAIN}.crt;
    ssl_certificate_key /etc/caddy/certs/${PANEL_DOMAIN}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    gzip on;
EOF
    append_nginx_single_443_path_proxy "$conf_file" "$SUB_URI_PATH" "$sub_backend"
    append_nginx_single_443_path_proxy "$conf_file" "$CLASH_URI_PATH" "$sub_backend"
    cat <<EOF >> "$conf_file"

    location / {
EOF
    write_nginx_single_443_proxy_headers >> "$conf_file"
    cat <<EOF >> "$conf_file"
        proxy_pass http://${panel_backend};
    }
}
EOF

    for i in "${!SITE_DOMAINS[@]}"; do
        site_domain="${SITE_DOMAINS[$i]}"
        [[ -n "$site_domain" ]] || continue
        site_backend=$(format_hostport "${SITE_BACKEND_ADDRS[$i]}" "${SITE_BACKEND_PORTS[$i]}")
        cat <<EOF >> "$conf_file"

server {
$(nginx_http_listen_directive "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    server_name ${site_domain};

    ssl_certificate /etc/caddy/certs/${site_domain}.crt;
    ssl_certificate_key /etc/caddy/certs/${site_domain}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    gzip on;

    location / {
EOF
        write_nginx_single_443_proxy_headers >> "$conf_file"
        cat <<EOF >> "$conf_file"
        proxy_pass http://${site_backend};
    }
}
EOF
    done
}

reload_nginx_after_config_quarantine() {
    command -v nginx >/dev/null 2>&1 || return 0
    nginx -t >/dev/null 2>&1 || return 1
    systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
}

quarantine_nginx_single_443_web_configs() {
    local keep_file="${1:-}"
    local conf_file moved=0
    for conf_file in /etc/nginx/conf.d/vps_sni_web_*.conf; do
        [[ -e "$conf_file" ]] || continue
        [[ -n "$keep_file" && "$conf_file" == "$keep_file" ]] && continue
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-sni-web" >/dev/null 2>&1 || true
        moved=$((moved + 1))
    done
    if [[ "$moved" -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 已隔离 ${moved} 个旧 443 Nginx 本地 Web 反代配置。${PLAIN}" "${YELLOW}⚠️ Isolated ${moved} Gejiu 443 Nginx local web reverse proxy configuration.${PLAIN}" "${YELLOW}⚠️ Карантин ${moved} Gejiu 443 Nginx Конфигурация обратного прокси-сервера локального веб-сайта.${PLAIN}")"
        reload_nginx_after_config_quarantine || echo -e "$(localized_text "${YELLOW}⚠️ Nginx 配置隔离后未能立即重载，后续应用阶段会再次校验。${PLAIN}" "${YELLOW}⚠️ Nginx failed to reload immediately after configuring isolation, and will be verified again in subsequent application stages.${PLAIN}" "${YELLOW}⚠️ Nginx не удалось перезагрузить сразу после настройки изоляции, и он будет проверен снова на последующих этапах применения.${PLAIN}")"
    fi
}

quarantine_caddy_single_443_web_configs() {
    local domain conf_file moved=0
    for domain in "$PANEL_DOMAIN" "${SITE_DOMAINS[@]}"; do
        [[ -n "$domain" ]] || continue
        conf_file="/etc/caddy/conf.d/${domain}.caddy"
        [[ -e "$conf_file" ]] || continue
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/caddy-sni-web" >/dev/null 2>&1 || true
        moved=$((moved + 1))
    done
    if [[ "$moved" -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 已隔离 ${moved} 个旧 443 Caddy 本地 Web 反代配置。${PLAIN}" "${YELLOW}⚠️ Isolated ${moved} Gejiu 443 Caddy local web reverse proxy configuration.${PLAIN}" "${YELLOW}⚠️ Карантин ${moved} Gejiu 443 Caddy Конфигурация обратного прокси-сервера локального веб-сайта.${PLAIN}")"
        if command -v caddy >/dev/null 2>&1 && [[ -f /etc/caddy/Caddyfile ]]; then
            caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 && \
                { systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true; }
        fi
    fi
}

apply_nginx_web_configs_for_single_443() {
    local conf_file
    conf_file=$(nginx_single_443_web_conf_path)
    install_nginx_http_if_needed || return 1
    ensure_nginx_http_conf_d || return 1
    harden_nginx_public_errors
    write_nginx_proxy_map_conf || return 1
    quarantine_legacy_nginx_https_proxy_configs
    quarantine_legacy_caddy_443_configs
    quarantine_caddy_single_443_web_configs
    quarantine_nginx_single_443_web_configs "$conf_file"
    write_nginx_single_443_web_config "$conf_file" || return 1
    if ! nginx -t; then
        echo -e "$(localized_text "${RED}❌ Nginx 本地 Web 反代配置校验失败，已隔离新增配置。${PLAIN}" "${RED}❌ Nginx The local Web reverse proxy configuration validation failed, and the new configuration has been isolated.${PLAIN}" "${RED}❌ Nginx Проверка конфигурации локального обратный прокси веб-страниц не удалась, и новая конфигурация была изолирована.${PLAIN}")"
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-sni-web" >/dev/null 2>&1 || true
        return 1
    fi
}

stage_and_validate_caddy_configs_for_single_443() {
    local plan_dir plan_conf_dir validate_log
    install_caddy_if_needed || return 1
    plan_dir=$(mktemp -d /tmp/vpso-caddy-plan.XXXXXX) || return 1
    chmod 700 "$plan_dir" 2>/dev/null || true
    plan_conf_dir="${plan_dir}/conf.d"
    validate_log="${plan_dir}/caddy-validate.log"
    mkdir -p "$plan_conf_dir" || return 1

    cat <<EOF > "${plan_dir}/Caddyfile"
{
    auto_https off
}

import ${plan_conf_dir}/*
EOF
    write_caddy_panel_config "${plan_conf_dir}/${PANEL_DOMAIN}.caddy"
    write_caddy_site_config "$plan_conf_dir"

    echo -e "$(localized_text "${CYAN}▶ 正在预校验 Caddy 计划配置，暂不改动 /etc/caddy...${PLAIN}" "${CYAN}▶ Pre-verifying the planned configuration of Caddy, /etc/caddy... will not be changed for the time being.${PLAIN}" "${CYAN}▶ Предварительная проверка запланированной конфигурации Caddy, /etc/caddy... пока не будет изменена.${PLAIN}")"
    if caddy validate --config "${plan_dir}/Caddyfile" >"$validate_log" 2>&1; then
        echo -e "$(localized_text "${GREEN}✅ Caddy 计划配置校验通过。${PLAIN}" "${GREEN}✅ Caddy plan configuration validation passed.${PLAIN}" "${GREEN}✅ Caddy Проверка конфигурации плана пройдена.${PLAIN}")"
        return 0
    fi

    echo -e "$(localized_text "${RED}❌ Caddy 计划配置校验失败，已停止写入和切换。${PLAIN}" "${RED}❌ Caddy Plan configuration validation failed, writing and switching have stopped.${PLAIN}" "${RED}❌ Caddy Проверка конфигурации плана не удалась, запись и переключение остановлены.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}预检目录：${plan_dir}${PLAIN}" "${YELLOW}Preflight check catalog: ${plan_dir}${PLAIN}" "${YELLOW}Каталог предварительной проверки : ${plan_dir}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}最近校验输出：${PLAIN}" "${YELLOW}Latest check output:${PLAIN}" "${YELLOW}последний результат проверки:${PLAIN}")"
    tail -n 80 "$validate_log" 2>/dev/null || true
    return 1
}

apply_caddy_configs_for_single_443() {
    quarantine_legacy_nginx_https_proxy_configs
    quarantine_nginx_single_443_web_configs
    stage_and_validate_caddy_configs_for_single_443 || return 1
    ensure_caddy_local_base_config || return 1
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    if ! caddy validate --config /etc/caddy/Caddyfile; then
        echo -e "$(localized_text "${RED}❌ Caddy 实际配置校验失败，拒绝继续。${PLAIN}" "${RED}❌ Caddy The actual configuration validation failed and continues is refused.${PLAIN}" "${RED}❌ Caddy Фактическая проверка конфигурации не удалась и в продолжении отказано.${PLAIN}")"
        return 1
    fi
}

apply_web_proxy_configs_for_single_443() {
    WEB_PROXY_ENGINE=$(current_web_proxy_engine)
    assert_web_proxy_whitelist_supported "${ENTRY_MODE:-$(get_entry_mode)}" "$WEB_PROXY_ENGINE" || return 1
    case "$WEB_PROXY_ENGINE" in
        nginx) apply_nginx_web_configs_for_single_443 ;;
        *) apply_caddy_configs_for_single_443 ;;
    esac
}

restart_web_proxy_for_single_443() {
    WEB_PROXY_ENGINE=$(current_web_proxy_engine)
    case "$WEB_PROXY_ENGINE" in
        nginx)
            if ! systemctl enable nginx >/dev/null 2>&1; then
                echo -e "$(localized_text "${RED}❌ nginx Web 反代开机启动设置失败。${PLAIN}" "${RED}❌ nginx Web reverse proxy startup setting failed.${PLAIN}" "${RED}❌ nginx Не удалось настроить запуск веб-прокси.${PLAIN}")"
                return 1
            fi
            systemctl restart nginx || return 1
            ;;
        *)
            if ! systemctl enable caddy >/dev/null 2>&1; then
                echo -e "$(localized_text "${RED}❌ Caddy Web 反代开机启动设置失败。${PLAIN}" "${RED}❌ Caddy Web reverse proxy startup setting failed.${PLAIN}" "${RED}❌ Caddy Не удалось настроить запуск веб-прокси.${PLAIN}")"
                return 1
            fi
            systemctl restart caddy || return 1
            ;;
    esac
}

issue_and_install_cert_for_domain() {
    local domain="$1"
    local cf_token="$2"
    local acme_bin="/root/.acme.sh/acme.sh"
    local acme_email
    acme_email=$(get_acme_account_email)
    if [[ ! -x "$acme_bin" ]]; then
        install_acme_sh "$acme_email" || return 1
    fi
    prepare_acme_account "$acme_bin" "$acme_email" || return 1
    mkdir -p /etc/caddy/certs /root/cert
    echo -e "$(localized_text "${CYAN}▶ 正在为 ${domain} 申请 Cloudflare DNS 证书...${PLAIN}" "${CYAN}▶ Applying for Cloudflare DNS certificate for ${domain}...${PLAIN}" "${CYAN}▶ Подача заявки на сертификат Cloudflare DNS для ${domain}...${PLAIN}")"
    issue_cf_dns_cert_with_retry "$domain" "$cf_token" "$acme_bin" || return 1
    "$acme_bin" --install-cert -d "$domain" --ecc \
        --fullchain-file "/etc/caddy/certs/${domain}.crt" \
        --key-file "/etc/caddy/certs/${domain}.key" \
        --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true; systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true" >/dev/null 2>&1 || return 1
    if id caddy >/dev/null 2>&1; then
        chown root:caddy "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key" >/dev/null 2>&1
        chmod 640 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
    else
        chmod 600 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
    fi
    ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
    ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
}

save_sni_stack_env() {
    mkdir -p /etc/vps-optimize
    local entry_mode web_proxy_engine strict_sni_gate site_domains_csv site_backend_addrs_csv site_backend_ports_csv
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
    web_proxy_engine=$(normalize_web_proxy_engine "${WEB_PROXY_ENGINE:-caddy}" 2>/dev/null || echo "caddy")
    strict_sni_gate=$(normalize_strict_sni_gate "${STRICT_SNI_GATE:-false}")
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
STRICT_SNI_GATE='${strict_sni_gate}'
WEB_PROXY_ENGINE='${web_proxy_engine}'
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
    local ssh_port remove_ports port
    local failures=()
    ssh_port=$(ss -lntp 2>/dev/null | awk '/sshd/ {print $4}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' | head -n1)
    ssh_port=${ssh_port:-22}
    confirm_danger \
        "$(localized_text "收紧 443 入口防火墙" "Tighten the Port 443 firewall" "Ужесточить правила брандмауэра для порта 443")" \
        "$(localized_text "只保留 SSH ${ssh_port:-22}/tcp 与公网入口 ${NGINX_LISTEN_PORT}/tcp，并撤销已知后端端口的公网放行规则。" "Keep only SSH ${ssh_port:-22}/tcp and public entry ${NGINX_LISTEN_PORT}/tcp, and revoke public allow rules for known backend ports." "Оставить только SSH ${ssh_port:-22}/tcp и публичный вход ${NGINX_LISTEN_PORT}/tcp, удалив разрешающие правила для известных внутренних портов.")" \
        "$(localized_text "保持当前 SSH 会话；可通过云厂商控制台重新放行端口或恢复防火墙规则。" "Keep the current SSH session open; use the provider console to restore firewall rules or allow ports again." "Не закрывайте текущий сеанс SSH; правила можно восстановить через консоль провайдера.")" \
        "$(localized_text "若 3x-ui 仍监听 0.0.0.0:${PANEL_LISTEN_PORT}，自动活动端口检测以后可能再次放行该端口。" "If 3x-ui still listens on 0.0.0.0:${PANEL_LISTEN_PORT}, automatic active-port detection may allow it again later." "Если 3x-ui продолжает слушать 0.0.0.0:${PANEL_LISTEN_PORT}, автоматическое обнаружение активных портов позднее может снова разрешить этот порт.")" || return 0
    remove_ports=("$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT" "${SITE_BACKEND_PORTS[@]}" "${TCP_ROUTE_PORTS[@]}" "${XRAY_SNI_ROUTE_PORTS[@]}" "40000" "8443" "1443" "2096" "3000")
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || failures+=("SSH ${ssh_port}/tcp")
        ufw allow "${NGINX_LISTEN_PORT}/tcp" >/dev/null 2>&1 || failures+=("entry ${NGINX_LISTEN_PORT}/tcp")
        for port in "${remove_ports[@]}"; do
            [[ "$port" == "$ssh_port" || "$port" == "$NGINX_LISTEN_PORT" ]] && continue
            ufw delete allow "${port}/tcp" >/dev/null 2>&1 || :
            ufw delete allow "${port}/udp" >/dev/null 2>&1 || :
        done
    elif command -v firewall-cmd >/dev/null 2>&1; then
        systemctl enable --now firewalld >/dev/null 2>&1 || failures+=("firewalld")
        firewall-cmd --permanent --add-port="${ssh_port}/tcp" >/dev/null 2>&1 || failures+=("SSH ${ssh_port}/tcp")
        firewall-cmd --permanent --add-port="${NGINX_LISTEN_PORT}/tcp" >/dev/null 2>&1 || failures+=("entry ${NGINX_LISTEN_PORT}/tcp")
        for port in "${remove_ports[@]}"; do
            [[ "$port" == "$ssh_port" || "$port" == "$NGINX_LISTEN_PORT" ]] && continue
            firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1 || :
            firewall-cmd --permanent --remove-port="${port}/udp" >/dev/null 2>&1 || :
        done
        firewall-cmd --reload >/dev/null 2>&1 || failures+=("firewalld reload")
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 ufw/firewalld，跳过防火墙收紧。${PLAIN}" "${YELLOW}⚠️ ufw/firewalld not detected, skipping firewall tightening.${PLAIN}" "${YELLOW}⚠️ ufw/firewalld не обнаружен, пропускается ужесточение брандмауэра.${PLAIN}")"
        return 0
    fi
    if (( ${#failures[@]} > 0 )); then
        echo -e "$(localized_text "${RED}❌ 防火墙收紧未完整应用：${failures[*]}。请保持当前 SSH 会话并检查防火墙状态。${PLAIN}" "${RED}❌ Firewall tightening was only partially applied: ${failures[*]}. Keep the current SSH session open and inspect the firewall state.${PLAIN}" "${RED}❌ Правила брандмауэра применены не полностью: ${failures[*]}. Не закрывайте текущий сеанс SSH и проверьте состояние брандмауэра.${PLAIN}")"
        return 1
    fi
    echo -e "$(localized_text "${GREEN}✅ 防火墙规则已应用：保留 SSH ${ssh_port}/tcp 与入口 ${NGINX_LISTEN_PORT}/tcp。${PLAIN}" "${GREEN}✅ Firewall rules applied: SSH ${ssh_port}/tcp and entry ${NGINX_LISTEN_PORT}/tcp are allowed.${PLAIN}" "${GREEN}✅ Правила применены: разрешены SSH ${ssh_port}/tcp и вход ${NGINX_LISTEN_PORT}/tcp.${PLAIN}")"
}

print_sni_stack_result() {
    local check_ports=()
    local check_regex=""
    local p entry_mode entry_label entry_listener web_engine web_label
    entry_mode="${ENTRY_MODE:-nginx-stream}"
    entry_mode=$(normalize_entry_mode_name "$entry_mode" 2>/dev/null || echo "nginx-stream")
    web_engine=$(current_web_proxy_engine)
    web_label=$(web_proxy_engine_label "$web_engine")
    case "$entry_mode" in
        "nginx-stream") entry_label="$(localized_text "Nginx Stream 模式" "Nginx Stream mode" "Режим Nginx Stream")"; entry_listener="nginx" ;;
        "xray-fallback") entry_label="$(localized_text "Xray Fallback 模式" "Xray Fallback mode" "Режим Xray Fallback")"; entry_listener="$(localized_text "xray/3x-ui 主入站" "xray/3x-ui main inbound" "Основное входящее подключение xray/3x-ui")" ;;
        "tcp-peek") entry_label="$(localized_text "TCP Peek + Splice 模式" "TCP Peek + Splice mode" "Режим TCP Peek + Splice")"; entry_listener="$(localized_text "vpso-mux 分流器" "vpso-mux traffic router" "Маршрутизатор трафика vpso-mux")" ;;
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
    echo -e "$(localized_text "${GREEN}✅ 443端口复用配置完成${PLAIN}" "${GREEN}✅ Port 443 Reuse route configuration completed${PLAIN}" "${GREEN}Конфигурация маршрутизации повторного использования порта 443 завершена${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "当前入口模式：${entry_label} (${entry_mode})" "Current entry mode: ${entry_label} (${entry_mode})" "Текущий режим ввода: ${entry_label} (${entry_mode})")"
    echo -e "$(localized_text "当前 Web 反代引擎：${web_label} (${web_engine})" "Current web reverse proxy engine: ${web_label} (${web_engine})" "Текущий движок веб-прокси: ${web_label} (${web_engine})")"
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
    echo -e "$(localized_text "  3.x 新安装 SSL：第 4 项 Skip SSL，再选 y 仅绑定 127.0.0.1" "3.x new-install SSL: option 4, Skip SSL, then y to bind only to 127.0.0.1" "SSL при новой установке 3.x: пункт 4 Skip SSL, затем y для привязки только к 127.0.0.1")"
    echo -e "$(localized_text "  2.x/旧配置面板证书路径/私钥路径：清空" "2.x/old configuration panel certificate path/private key path: clear" "2.x/старый путь к сертификату панели конфигурации/путь к секретному ключу: очистить")"
    echo -e "$(localized_text "  Web 反代引擎后端连接：http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Web reverse proxy engine backend connection: http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Серверное соединение механизма веб-прокси: http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}")"
    echo -e "  Panel URL / Public URL / External URL：https://${PANEL_DOMAIN}${PANEL_WEB_PATH}"
    echo -e "  Subscription URI Path：${SUB_URI_PATH}"
    echo -e "  Subscription External URL：https://${PANEL_DOMAIN}${SUB_URI_PATH}"
    echo -e "  Clash/Mihomo URI Path：${CLASH_URI_PATH}"
    echo -e "  Clash/Mihomo External URL：https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    echo -e "$(localized_text "${YELLOW}  不建议使用 webBasePath=/，随机面板路径能降低被批量扫描命中的概率。${PLAIN}" "${YELLOW}It is not recommended to use webBasePath=/. Random panel paths can reduce the probability of being hit by batch scanning.${PLAIN}" "${YELLOW}Не рекомендуется использовать webBasePath=/. Случайное расположение панелей может снизить вероятность попадания в пакетное сканирование.${PLAIN}")"
    echo -e "$(localized_text "  2.x/旧配置订阅证书路径/私钥路径：清空" "2.x/old configuration subscription certificate path/private key path: clear" "2.x/путь сертификата подписки старой конфигурации/путь закрытого ключа: очистить")"
    echo -e ""
    echo -e "$(localized_text "${BOLD}三、Xray / 3x-ui+Reality 入站这样填${PLAIN}" "${BOLD}3. Configure the Xray / 3x-ui+Reality inbound as follows${PLAIN}" "${BOLD}3. Заполните входящее подключение Xray / 3x-ui+Reality так${PLAIN}")"
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
    echo -e "$(localized_text "  ERR_TOO_MANY_REDIRECTS：通常是 3.x 误启用 3x-ui SSL、2.x/旧配置证书路径没清空，或外部地址/路径配置不一致" "ERR_TOO_MANY_REDIRECTS: Usually 3.x mistakenly enabled 3x-ui SSL, 2.x/old configuration certificate path is not cleared, or the external address/path configuration is inconsistent" "ERR_TOO_MANY_REDIRECTS: Обычно 3.x ошибочно включен 3x-ui SSL, путь сертификата конфигурации 2.x/старая не очищается или конфигурация внешнего адреса/пути несовместима.")"
    echo -e "$(localized_text "  HTTP 404：先检查访问路径是否等于 3x-ui 的 webBasePath，再检查 Web 反代引擎是否反代到 ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "HTTP 404: First check whether the access path is equal to the webBasePath of 3x-ui, and then check whether the Web reverse proxy engine is reverse proxy to ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "HTTP 404: сначала проверьте, равен ли путь доступа webBasePath 3x-ui, а затем проверьте, соответствует ли обратный прокси-сервер веб-обратного прокси ${PANEL_LISTEN_ADDR}: ${PANEL_LISTEN_PORT}.")"
    echo -e "$(localized_text "  502 Bad Gateway：通常是 3x-ui 没启动、端口不对，或 3x-ui 后端仍是 HTTPS" "502 Bad Gateway: Usually 3x-ui is not started, the port is wrong, or 3x-ui backend is still HTTPS" "502 Bad Gateway: обычно 3x-ui не запускается, порт неправильный или бэкенд 3x-ui все еще остается HTTPS.")"
    echo -e ""
    echo -e "$(localized_text "${BOLD}五、入口与后端配置${PLAIN}" "${BOLD}5. Entry and backend configuration${PLAIN}" "${BOLD}5. Входная и серверная конфигурация${PLAIN}")"
    echo -e "  ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${entry_listener}"
    echo -e "  ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> ${web_label}"
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
    if [[ "$web_engine" == "caddy" ]]; then
        echo -e "  caddy validate --config /etc/caddy/Caddyfile"
        echo -e "  journalctl -u caddy -n 80 --no-pager"
    fi
    echo -e "  curl -I http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}/"
    echo -e "$(localized_text "  openssl s_client -connect 服务器IP:${NGINX_LISTEN_PORT} -servername ${PANEL_DOMAIN}" "openssl s_client -connect server IP:${NGINX_LISTEN_PORT} -servername ${PANEL_DOMAIN}" "openssl s_client -IP-адрес сервера подключения: ${NGINX_LISTEN_PORT} -имя_сервера ${PANEL_DOMAIN}")"
    echo -e "$(localized_text "  openssl s_client -connect 服务器IP:${NGINX_LISTEN_PORT} -servername ${REALITY_SNI}" "openssl s_client -connect server IP:${NGINX_LISTEN_PORT} -servername ${REALITY_SNI}" "openssl s_client -IP-адрес сервера подключения: ${NGINX_LISTEN_PORT} -имя_сервера ${REALITY_SNI}")"
    [[ "$web_engine" == "nginx" ]] && echo -e "  journalctl -u nginx -n 80 --no-pager"
    echo -e "  journalctl -u x-ui -u 3x-ui -n 80 --no-pager"
    echo -e ""
    case "$entry_mode" in
        "xray-fallback")
            echo -e "$(localized_text "${RED}绝对不要做：Web 反代引擎直接监听公网 443；3x-ui 面板、订阅服务或额外本地入站暴露公网；3.x 安装时启用 3x-ui SSL 或 2.x/旧配置证书路径未清空就跑 Web fallback；把 REALITY dest/serverNames 写成面板域名。${PLAIN}" "${RED}Do not: Web reverse proxy engine directly listens on the public port 443; 3x-ui panel, subscription service or additional local inbound exposes the public; enable 3x-ui SSL during 3.x installation or run Web fallback without clearing the certificate path of 2.x/old configuration; set REALITY dest/serverNames to the panel domain.${PLAIN}" "${RED}не должен делать: веб-механизм обратный прокси напрямую прослушивает публичный порт 443; Панель 3x-ui, служба подписки или дополнительный локальное входящее подключение предоставляют доступ к публичной сети; включите 3x-ui SSL во время установки 3.x или запустите веб-резервный вариант без очистки пути сертификата конфигурации 2.x/старой; put REALITY dest/serverNames записывается как доменное имя панели.${PLAIN}")"
            ;;
        *)
            echo -e "$(localized_text "${RED}绝对不要做：Web 反代引擎直接监听公网 443；Xray/3x-ui 主入站直接占用公网 443；3x-ui 面板或新增本地入站暴露公网；3.x 安装时启用 3x-ui SSL 或 2.x/旧配置证书路径未清空就跑 443；把 REALITY dest/serverNames 写成面板域名。${PLAIN}" "${RED}Do not: Web reverse proxy engine directly listens on the public port 443; Xray/3x-ui main inbound directly occupies the public port 443; 3x-ui panel or adds local inbound to expose the public; 3.x enable 3x-ui SSL or 2.x/old configuration certificate path is not cleared and 443 will occur; write REALITY dest/serverNames as the panel domain.${PLAIN}" "${RED}не должен делать: веб-механизм обратный прокси напрямую прослушивает публичный порт 443; основное входящее подключение Xray/3x-ui непосредственно занимает публичный порт 443; Панель 3x-ui или добавляет локальное входящее подключение для доступа к публичной сети; Путь к сертификату конфигурации 3.x Enable 3x-ui SSL или 2.x/old не очищается и возникает ошибка 443; напишите REALITY dest/serverNames в качестве имени домена панели.${PLAIN}")"
            ;;
    esac
}

apply_sni_stack_runtime_config() {
    local backup_dir current_mode
    current_mode="${ENTRY_MODE:-$(get_entry_mode)}"
    current_mode=$(normalize_entry_mode_name "$current_mode" 2>/dev/null || echo "nginx-stream")

    create_sni_stack_backup
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    guard_current_ssh_not_on_entry_port "$(localized_text "重新应用 443端口复用运行参数" "Reapply Port 443 Reuse Run Parameters" "Повторно применить 443 отдельных рабочих параметра")" || return 1
    check_entry_mode_dependencies "$current_mode" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "入口模式依赖检查失败" "Entry mode dependency check failed" "Проверка зависимости режима входа не удалась")"; return 1; }
    preflight_entry_mode_before_cutover "$current_mode" || { echo -e "$(localized_text "${RED}❌ 入口模式 ${current_mode} 预检失败，公网 443 未重新应用。${PLAIN}" "${RED}❌ entry mode ${current_mode} Preflight failed, public port 443 was not reapplied.${PLAIN}" "${RED}❌ Режим входа ${current_mode} Не удалось выполнить предварительную проверку, конфигурация публичного порта 443 не была применена повторно.${PLAIN}")"; return 1; }
    stop_public_443_entry_services_for_target "$current_mode" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "停止旧公网 443 入口服务失败" "Stop the old public port 443 entry service failed" "Остановить старую публичную сеть 443, служба входа не удалась")"; return 1; }
    apply_entry_mode_by_name "$current_mode" "$backup_dir" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "入口模式 ${current_mode} 应用失败" "Entry mode ${current_mode} application failed" "Режим входа в приложение ${current_mode} не выполнен.")"; return 1; }
    ENTRY_MODE="$current_mode"
    save_sni_stack_env
    write_single_443_engine_state "$(entry_mode_engine_name "$current_mode")" "$backup_dir"
    generate_caddy_cf_manifest
}
