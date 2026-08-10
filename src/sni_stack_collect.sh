# shellcheck shell=bash
# Interactive 443 stack configuration collection.

collect_sni_stack_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}443端口复用配置${PLAIN}" "${BOLD}Port 443 Reuse configuration${PLAIN}" "${BOLD}Конфигурация повторного использования порта 443${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}公网 443 将由你选择的入口模式监听；Web 域名、Web 反代引擎、证书和白名单为三种模式共享。${PLAIN}" "${YELLOW}Public port 443 will be monitored by the entry mode you choose; the Web domain, Web reverse proxy engine, certificate and whitelist are shared by the three modes.${PLAIN}" "${YELLOW}публичный порт 443 будет контролироваться в выбранном вами режиме входа; имя веб-домена, механизм веб-прокси, сертификат и белый список являются общими для всех трех режимов.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}Caddy/Xray/3x-ui 本地后端默认绑定 127.0.0.1。${PLAIN}" "${YELLOW}Caddy/Xray/3x-ui The local backend is bound to 127.0.0.1 by default.${PLAIN}" "${YELLOW}Caddy/Xray/3x-ui По умолчанию локальный сервер привязан к 127.0.0.1.${PLAIN}")"
    echo -e "------------------------------------------------"

    read_trimmed PANEL_DOMAIN "$(localized_text "面板域名（必填，例如 panel.example.com）: " "Panel domain (required, for example panel.example.com):" "Доменное имя Panel (обязательно, например Panel.example.com):")"
    SITE_DOMAINS=()
    SITE_BACKEND_ADDRS=()
    SITE_BACKEND_PORTS=()
    TCP_ROUTE_SNIS=()
    TCP_ROUTE_ADDRS=()
    TCP_ROUTE_PORTS=()
    SNI_IP_WHITELIST_DOMAINS=()
    SNI_IP_WHITELIST_RANGES=()
    local site_domains_input
    site_domains_input=$(ask_with_default "$(localized_text "网站/反代域名（可选，多个用英文逗号分隔，例如 site1.example.com,site2.example.com）" "Website/reverse domain (optional, separate multiple with commas, such as site1.example.com,site2.example.com)" "Веб-сайт/обратное доменное имя (необязательно, разделяйте запятыми, например site1.example.com,site2.example.com)")" "")
    split_csv_to_array "$site_domains_input" SITE_DOMAINS
    echo -e "$(localized_text "${YELLOW}REALITY 伪装 SNI 请填写外部真实 HTTPS 站点域名，不要填写面板域名或节点域名。${PLAIN}" "${YELLOW}REALITY Disguise SNI Please fill in the external real HTTPS site domain, do not fill in the panel domain or node domain.${PLAIN}" "${YELLOW}REALITY Маскировка SNI Пожалуйста, укажите внешнее реальное доменное имя сайта HTTPS, не заполняйте имя домена панели или имя домена узла.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}模板示例：your-reality-sni.example.com（请替换成你自己选择的真实站点）${PLAIN}" "${YELLOW}Template example: your-reality-sni.example.com (please replace it with the real site of your choice)${PLAIN}" "${YELLOW}Пример шаблона : your-reality-sni.example.com (замените его реальным сайтом по вашему выбору)${PLAIN}")"
    read_trimmed REALITY_SNI "$(localized_text "REALITY 伪装 SNI（必填）: " "REALITY Disguise SNI (required):" "REALITY Маскировка SNI (обязательно):")"
    NGINX_LISTEN_ADDR=$(ask_with_default "$(localized_text "Nginx 公网监听地址" "Nginx public listening address" "Nginx адрес прослушивания публичной сети")" "0.0.0.0")
    NGINX_LISTEN_PORT=$(ask_with_default "$(localized_text "Nginx 公网监听端口" "Nginx public listening port" "Порт прослушивания публичной сети Nginx")" "443")

    local advanced_mode
    read_trimmed advanced_mode "$(localized_text "是否进入高级模式并允许修改本地服务监听地址？(Y/n，默认 y): " "Do you want to enter advanced mode and allow modification of the local service listening address? (Y/n, default y):" "Хотите войти в расширенный режим и разрешить изменение адреса прослушивания локальной службы? (Да/нет, по умолчанию y):")"
    if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
        CADDY_LISTEN_ADDR=$(ask_with_default "$(localized_text "Caddy 本地监听地址" "Caddy local listening address" "Caddy локальный адрес прослушивания")" "127.0.0.1")
        XRAY_LISTEN_ADDR=$(ask_with_default "$(localized_text "Xray REALITY 本地监听地址" "Xray REALITY local listening address" "Xray REALITY локальный адрес прослушивания")" "127.0.0.1")
        PANEL_LISTEN_ADDR=$(ask_with_default "$(localized_text "3x-ui 面板监听地址" "3x-ui panel listening address" "Адрес прослушивания панели 3x-ui")" "127.0.0.1")
        SUB_LISTEN_ADDR=$(ask_with_default "$(localized_text "3x-ui 订阅服务监听地址" "3x-ui Subscription service listening address" "3x-ui Адрес прослушивания службы подписки")" "127.0.0.1")
    else
        CADDY_LISTEN_ADDR="127.0.0.1"
        XRAY_LISTEN_ADDR="127.0.0.1"
        PANEL_LISTEN_ADDR="127.0.0.1"
        SUB_LISTEN_ADDR="127.0.0.1"
        echo -e "$(localized_text "${GREEN}普通模式：Caddy/Xray/3x-ui/订阅/网站后端均使用 127.0.0.1。${PLAIN}" "${GREEN}Normal mode: Caddy/Xray/3x-ui/subscription/website backend all use 127.0.0.1.${PLAIN}" "${GREEN}Обычный режим : Caddy/Xray/3x-ui/subscription/backend веб-сайта используют 127.0.0.1.${PLAIN}")"
    fi

    CADDY_LISTEN_PORT=$(ask_with_default "$(localized_text "Caddy 本地监听端口" "Caddy local listening port" "Caddy локальный порт прослушивания")" "8443")
    XRAY_LISTEN_PORT=$(ask_with_default "$(localized_text "Xray REALITY 本地监听端口" "Xray REALITY local listening port" "Xray REALITY локальный порт прослушивания")" "1443")
    PANEL_LISTEN_PORT=$(ask_with_default "$(localized_text "3x-ui 面板端口" "3x-ui panel port" "Порт панели 3x-ui")" "40000")
    PANEL_WEB_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "3x-ui 面板公网路径 / webBasePath（必须和面板 url 根路径一致）" "3x-ui public panel path / webBasePath (must match the panel URL root path)" "Публичный путь панели 3x-ui / webBasePath (должен совпадать с корневым URL панели)")" "/panel/")")
    SUB_LISTEN_PORT=$(ask_with_default "$(localized_text "3x-ui 订阅服务端口（可自定义）" "3x-ui Subscription service port (customizable)" "3x-ui Порт службы подписки (настраиваемый)")" "2096")
    SUB_URI_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "3x-ui 普通订阅路径前缀（不带端口和客户端 Subscription，建议写 /sub/）" "3x-ui standard subscription path prefix (without port or client identifier; recommended: /sub/)" "Префикс обычной подписки 3x-ui (без порта и идентификатора клиента; рекомендуется /sub/)")" "/sub/")")
    CLASH_URI_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "3x-ui Clash/Mihomo 订阅路径前缀（不带客户端 Subscription，建议写 /clash/）" "3x-ui Clash/Mihomo subscription path prefix (without client identifier; recommended: /clash/)" "Префикс подписки Clash/Mihomo в 3x-ui (без идентификатора клиента; рекомендуется /clash/)")" "/clash/")")
    local panel_whitelist_enabled panel_whitelist_input panel_whitelist_ranges current_client_ip
    local -a panel_whitelist_array=()
    read_trimmed panel_whitelist_enabled "$(localized_text "是否为面板域名启用 IP 白名单？(y/N，默认 N): " "Enable an IP allowlist for the panel domain? (y/N, default N): " "Включить список разрешённых IP-адресов для домена панели? (y/N, по умолчанию N): ")"
    if [[ "$panel_whitelist_enabled" =~ ^[Yy]$ ]]; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "$(localized_text "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}" "${YELLOW}The current source IP of SSH may be: ${current_client_ip}. Please confirm that it has been added to the whitelist.${PLAIN}" "${YELLOW}Текущий исходный IP-адрес SSH может быть: ${current_client_ip}. Пожалуйста, подтвердите, что он был добавлен в белый список.${PLAIN}")"
        read_trimmed panel_whitelist_input "$(localized_text "请输入允许访问面板域名的 IP/CIDR（多个用空格或英文逗号分隔）: " "Please enter the IP/CIDR of the domain that is allowed to access the panel (separate multiple by spaces or commas):" "Пожалуйста, введите IP/CIDR доменного имени, которому разрешен доступ к панели (разделяйте кратные пробелами или запятыми):")"
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
            if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
                SITE_BACKEND_ADDRS[$i]=$(ask_with_default "$(localized_text "网站 ${SITE_DOMAINS[$i]} 的后端地址" "The backend address of the website ${SITE_DOMAINS[$i]}" "Внутренний адрес сайта ${SITE_DOMAINS[$i]}")" "127.0.0.1")
            else
                SITE_BACKEND_ADDRS[$i]="127.0.0.1"
            fi
            SITE_BACKEND_PORTS[$i]=$(ask_with_default "$(localized_text "网站 ${SITE_DOMAINS[$i]} 的后端端口" "Backend port of website ${SITE_DOMAINS[$i]}" "Внутренний порт веб-сайта ${SITE_DOMAINS[$i]}")" "$default_site_port")
            default_site_port=$((default_site_port + 1))
        done
    fi

    echo -e "$(localized_text "${YELLOW}请确认 3x-ui 面板设置 -> 常规 -> 证书、订阅设置 -> 证书 路径已经清空。${PLAIN}" "${YELLOW}Please confirm that the 3x-ui Panel Settings -> General -> Certificate, Subscription Settings -> Certificate path has been cleared.${PLAIN}" "${YELLOW}Подтвердите, что настройки панели 3x-ui -> Общие -> Сертификат, Настройки подписки -> Путь к сертификату удалены.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}本向导会让 Caddy 通过 HTTP 连接 ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} 和 ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}。${PLAIN}" "${YELLOW}This wizard will allow Caddy to connect ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} and ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT} through HTTP.${PLAIN}" "${YELLOW}Этот мастер позволит Caddy соединить ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} и ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT} через HTTP.${PLAIN}")"
    confirm_default_no "$(localized_text "确认已经清空面板和订阅证书路径？(y/N): " "Confirm that the panel and subscription certificate paths are already clear. (y/N): " "Подтвердите, что пути сертификатов панели и подписки уже очищены. (y/N): ")" || { echo -e "$(localized_text "${YELLOW}请先在 3x-ui 中清空证书路径，保存并重启面板。${PLAIN}" "${YELLOW}Clear the certificate paths in 3x-ui, save, and restart the panel first.${PLAIN}" "${YELLOW}Сначала очистите пути сертификатов в 3x-ui, сохраните изменения и перезапустите панель.${PLAIN}")"; return 1; }

    echo -e "$(localized_text "${CYAN}请输入 Cloudflare API Token（需 Zone.DNS.Edit + Zone.Zone.Read）${PLAIN}" "${CYAN}Please enter Cloudflare API Token (requires Zone.DNS.Edit + Zone.Zone.Read)${PLAIN}" "${CYAN}Введите токен API Cloudflare (требуется Zone.DNS.Edit + Zone.Zone.Read)${PLAIN}")"
    read_secret_trimmed CF_TOKEN "CF Token: "

    PANEL_DOMAIN=$(normalize_domain_input "$PANEL_DOMAIN")
    REALITY_SNI=$(normalize_domain_input "$REALITY_SNI")
    local site_idx
    for site_idx in "${!SITE_DOMAINS[@]}"; do
        SITE_DOMAINS[$site_idx]=$(normalize_domain_input "${SITE_DOMAINS[$site_idx]}")
        SITE_BACKEND_ADDRS[$site_idx]=$(normalize_backend_addr_input "${SITE_BACKEND_ADDRS[$site_idx]:-127.0.0.1}")
    done

    if ! is_valid_domain "$PANEL_DOMAIN"; then echo -e "$(localized_text "${RED}❌ 面板域名无效。${PLAIN}" "${RED}❌ The panel domain is invalid.${PLAIN}" "${RED}❌ Недопустимое доменное имя панели.${PLAIN}")"; return 1; fi
    if ! is_valid_domain "$REALITY_SNI"; then echo -e "$(localized_text "${RED}❌ REALITY SNI 无效。${PLAIN}" "${RED}❌ REALITY SNI is invalid.${PLAIN}" "${RED}❌ REALITY SNI недействителен.${PLAIN}")"; return 1; fi
    check_domain_dns_sanity "$PANEL_DOMAIN" "$(localized_text "面板域名" "Panel domain" "Доменное имя панели")" "prompt" || return 1
    check_domain_dns_sanity "$REALITY_SNI" "REALITY SNI" "prompt" || return 1
    local site_domain seen_domains
    seen_domains=" ${PANEL_DOMAIN} ${REALITY_SNI} "
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ -z "$site_domain" ]] && continue
        if ! is_valid_domain "$site_domain"; then echo -e "$(localized_text "${RED}❌ 网站/反代域名无效：${site_domain}${PLAIN}" "${RED}❌ Invalid website/reverse domain: ${site_domain}${PLAIN}" "${RED}❌ Неверный веб-сайт/обратное доменное имя: ${site_domain}.${PLAIN}")"; return 1; fi
        if [[ "$site_domain" == "$PANEL_DOMAIN" || "$site_domain" == "$REALITY_SNI" || "$seen_domains" == *" ${site_domain} "* ]]; then
            echo -e "$(localized_text "${RED}❌ 面板域名、网站/反代域名、REALITY SNI 不能相同：${site_domain}${PLAIN}" "${RED}❌ Panel domain, website/reverse domain, REALITY SNI cannot be the same: ${site_domain}${PLAIN}" "${RED}❌ Доменное имя панели, веб-сайт/обратное доменное имя, REALITY SNI не могут быть одинаковыми: ${site_domain}${PLAIN}")"
            return 1
        fi
        check_domain_dns_sanity "$site_domain" "$(localized_text "网站/反代域名" "Website/reverse domain" "Веб-сайт/обратное доменное имя")" "prompt" || return 1
        seen_domains+=" ${site_domain} "
    done

    local p a
    for p in "$NGINX_LISTEN_PORT" "$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT" "${SITE_BACKEND_PORTS[@]}"; do
        is_valid_port "$p" || { echo -e "$(localized_text "${RED}❌ 端口无效：${p}${PLAIN}" "${RED}❌ Invalid port: ${p}${PLAIN}" "${RED}❌ Неверный порт: ${p}.${PLAIN}")"; return 1; }
    done
    for a in "$NGINX_LISTEN_ADDR" "$CADDY_LISTEN_ADDR" "$XRAY_LISTEN_ADDR" "$PANEL_LISTEN_ADDR" "$SUB_LISTEN_ADDR"; do
        is_valid_listen_addr "$a" || { echo -e "$(localized_text "${RED}❌ 监听地址无效：${a}${PLAIN}" "${RED}❌ The listening address is invalid: ${a}${PLAIN}" "${RED}❌ Неверный адрес прослушивания: ${a}.${PLAIN}")"; return 1; }
    done
    for a in "${SITE_BACKEND_ADDRS[@]}"; do
        is_valid_backend_addr "$a" || { echo -e "$(localized_text "${RED}❌ 后端地址无效：${a}${PLAIN}" "${RED}❌ Invalid backend address: ${a}${PLAIN}" "${RED}❌ Неверный внутренний адрес: ${a}.${PLAIN}")"; return 1; }
    done
    is_valid_path_prefix "$PANEL_WEB_PATH" || { echo -e "$(localized_text "${RED}❌ 面板公网路径无效：${PANEL_WEB_PATH}${PLAIN}" "${RED}❌ The public path of the panel is invalid: ${PANEL_WEB_PATH}${PLAIN}" "${RED}❌ Неверный путь панели в публичной сети: ${PANEL_WEB_PATH}.${PLAIN}")"; return 1; }
    is_valid_path_prefix "$SUB_URI_PATH" || { echo -e "$(localized_text "${RED}❌ 普通订阅路径前缀无效：${SUB_URI_PATH}${PLAIN}" "${RED}❌ The common subscription path prefix is invalid: ${SUB_URI_PATH}${PLAIN}" "${RED}❌ Неверный префикс общего пути подписки: ${SUB_URI_PATH}.${PLAIN}")"; return 1; }
    is_valid_path_prefix "$CLASH_URI_PATH" || { echo -e "$(localized_text "${RED}❌ Clash/Mihomo 订阅路径前缀无效：${CLASH_URI_PATH}${PLAIN}" "${RED}❌ Clash/Mihomo Invalid subscription path prefix: ${CLASH_URI_PATH}${PLAIN}" "${RED}❌ Clash/Mihomo Неверный префикс пути подписки: ${CLASH_URI_PATH}${PLAIN}")"; return 1; }
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
    [[ "$NGINX_LISTEN_PORT" != "443" ]] && echo -e "$(localized_text "${YELLOW}⚠️  Nginx 公网端口不是 443，不推荐。${PLAIN}" "${YELLOW}⚠️ The public port of Nginx is not 443 and is not recommended.${PLAIN}" "${YELLOW}⚠️ Порт публичной сети Nginx не 443 и не рекомендуется.${PLAIN}")"

    warn_if_public_bind "Caddy" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    warn_if_public_bind "$(localized_text "3x-ui 面板" "3x-ui panel" "Панель 3x-ui")" "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT" || return 1
    warn_if_public_bind "$(localized_text "3x-ui 订阅服务" "3x-ui Subscription Service" "Служба подписки 3x-ui")" "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT" || return 1

    if [[ -z "$CF_TOKEN" || ${#CF_TOKEN} -lt 20 ]]; then echo -e "$(localized_text "${RED}❌ Cloudflare Token 长度异常。${PLAIN}" "${RED}❌ Cloudflare Token length is abnormal.${PLAIN}" "${RED}❌ Cloudflare Неверная длина токена.${PLAIN}")"; return 1; fi
    echo -e "$(localized_text "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}" "${CYAN}▶ Verifying online Cloudflare Token...${PLAIN}" "${CYAN}▶ Проверка токена Cloudflare онлайн...${PLAIN}")"
    verify_cf_token_online "$CF_TOKEN"
    local verify_rc=$?
    if [[ "$verify_rc" -eq 0 ]]; then
        echo -e "$(localized_text "${GREEN}✅ Cloudflare Token 校验通过。${PLAIN}" "${GREEN}✅ Cloudflare Token verification passed.${PLAIN}" "${GREEN}✅ Cloudflare Проверка токена пройдена.${PLAIN}")"
    elif [[ "$verify_rc" -eq 2 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}" "${YELLOW}⚠️ curl is not installed, skip online verification.${PLAIN}" "${YELLOW}⚠️ curl не установлен, пропустите онлайн-проверку.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ Cloudflare Token 校验失败。${PLAIN}" "${RED}❌ Cloudflare Token verification failed.${PLAIN}" "${RED}❌ Cloudflare Проверка токена не удалась.${PLAIN}")"
        return 1
    fi
}
