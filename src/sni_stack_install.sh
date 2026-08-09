# shellcheck shell=bash
# Port 443 Reuse collection, installation, rendering, certificates, and runtime apply flows.

collect_sni_stack_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}443端口复用配置${PLAIN}" "${BOLD}Port 443 Reuse configuration${PLAIN}" "${BOLD}Конфигурация повторного использования порта 443${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}公网 443 将由你选择的入口模式监听；Web 域名、反代引擎、证书和白名单为三种模式共享。${PLAIN}" "${YELLOW}Public port 443 will be monitored by the entry mode you choose; the web domain, reverse proxy engine, certificate and whitelist are shared by the three modes.${PLAIN}" "${YELLOW}Публичный порт  443 будет контролироваться выбранным вами режимом входа; имя веб-домена, механизм обратного прокси-сервера, сертификат и белый список являются общими для всех трех режимов.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}Web 反代引擎、Xray/3x-ui 本地后端默认绑定 127.0.0.1。${PLAIN}" "${YELLOW}Web reverse proxy engine and Xray/3x-ui local backend are bound to 127.0.0.1 by default.${PLAIN}" "${YELLOW}Механизм обратный прокси Web и локальный бэкэнд Xray/3x-ui по умолчанию привязаны к 127.0.0.1.${PLAIN}")"
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
    read_trimmed panel_domain_input "$(localized_text "面板域名（必填，例如 panel.example.com）: " "Panel domain (required, for example panel.example.com):" "Доменное имя Panel (обязательно, например Panel.example.com):")"
    PANEL_DOMAIN="$panel_domain_input"
    local web_engine_choice
    WEB_PROXY_ENGINE="caddy"
    echo -e "$(localized_text "${CYAN}请选择 443端口复用 Web 反代引擎：${PLAIN}" "${CYAN}Please select Port 443 Reuse Web reverse proxy engine:${PLAIN}" "${CYAN}Выберите механизм веб-прокси с повторным использованием порта 443:${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  1. Caddy 本地 HTTPS 反代${PLAIN} ${YELLOW}(默认，兼容现有 443端口复用配置)${PLAIN}" "${GREEN}1. Caddy local HTTPS reverse proxy   (default, compatible with existing Port 443 Reuse configuration)${PLAIN}" "${GREEN}1. Caddy локальный HTTPS обратный прокси (по умолчанию, совместимо с существующей конфигурацией повторного использования порта 443)${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  2. Nginx 本地 HTTPS 反代${PLAIN} ${YELLOW}(只监听本地端口，不抢公网 443)${PLAIN}" "${GREEN}2. Nginx local HTTPS reverse proxy (only listens to the local port, does not grab the public port 443)${PLAIN}" "${GREEN}2. Nginx локальный HTTPS обратный прокси-сервер   (прослушивает только локальный порт и не захватывает публичный порт 443)${PLAIN}")"
    read_trimmed web_engine_choice "$(localized_text "请选择 Web 反代引擎（默认 1）: " "Please select a web reverse proxy engine (default 1):" "Пожалуйста, выберите механизм веб-прокси (по умолчанию 1):")"
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
    site_domains_input=$(ask_with_default "$(localized_text "网站/反代域名（可选，多个用英文逗号分隔，例如 site1.example.com,site2.example.com）" "Website/reverse domain (optional, separate multiple with commas, such as site1.example.com,site2.example.com)" "Веб-сайт/обратное доменное имя (необязательно, разделяйте запятыми, например site1.example.com,site2.example.com)")" "")
    split_csv_to_array "$site_domains_input" SITE_DOMAINS
    site_domain_raw_inputs=("${SITE_DOMAINS[@]}")
    echo -e "$(localized_text "${YELLOW}REALITY 伪装 SNI 请填写外部真实 HTTPS 站点域名，不要填写面板域名或节点域名。${PLAIN}" "${YELLOW}REALITY Disguise SNI Please fill in the external real HTTPS site domain, do not fill in the panel domain or node domain.${PLAIN}" "${YELLOW}REALITY Маскировка SNI Пожалуйста, укажите внешнее реальное доменное имя сайта HTTPS, не заполняйте имя домена панели или имя домена узла.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}模板示例：your-reality-sni.example.com（请替换成你自己选择的真实站点）${PLAIN}" "${YELLOW}Template example: your-reality-sni.example.com (please replace it with the real site of your choice)${PLAIN}" "${YELLOW}Пример шаблона : your-reality-sni.example.com (замените его реальным сайтом по вашему выбору)${PLAIN}")"
    read_trimmed reality_sni_input "$(localized_text "REALITY 伪装 SNI（必填）: " "REALITY Disguise SNI (required):" "REALITY Маскировка SNI (обязательно):")"
    REALITY_SNI="$reality_sni_input"
    NGINX_LISTEN_ADDR=$(ask_with_default "$(localized_text "Nginx 公网监听地址" "Nginx public listening address" "Nginx адрес прослушивания публичной сети")" "0.0.0.0")
    NGINX_LISTEN_PORT=$(ask_with_default "$(localized_text "Nginx 公网监听端口" "Nginx public listening port" "Порт прослушивания публичной сети Nginx")" "443")

    local advanced_mode
    read_trimmed advanced_mode "$(localized_text "是否进入高级模式并允许修改本地服务监听地址？(Y/n，默认 y): " "Do you want to enter advanced mode and allow modification of the local service listening address? (Y/n, default y):" "Хотите войти в расширенный режим и разрешить изменение адреса прослушивания локальной службы? (Да/нет, по умолчанию y):")"
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
        echo -e "$(localized_text "${GREEN}普通模式：Web 反代引擎/Xray/3x-ui/订阅/网站后端均使用 127.0.0.1。${PLAIN}" "${GREEN}Normal mode: Web reverse proxy engine/Xray/3x-ui/subscription/website backend all use 127.0.0.1.${PLAIN}" "${GREEN}Обычный режим : механизм веб-прокси/Xray/3x-ui/подписка/бэкэнд веб-сайта используют 127.0.0.1.${PLAIN}")"
    fi

    CADDY_LISTEN_PORT=$(ask_with_default "$(localized_text "$(web_proxy_engine_label "$WEB_PROXY_ENGINE")监听端口" "$(web_proxy_engine_label \"$WEB_PROXY_ENGINE\") listening port" "Порт прослушивания $(web_proxy_engine_label \"$WEB_PROXY_ENGINE\")")" "8443")
    XRAY_LISTEN_PORT=$(ask_with_default "$(localized_text "Xray REALITY 本地监听端口" "Xray REALITY local listening port" "Xray REALITY локальный порт прослушивания")" "1443")
    PANEL_LISTEN_PORT=$(ask_with_default "$(localized_text "3x-ui 面板端口" "3x-ui panel port" "Порт панели 3x-ui")" "$default_panel_port")
    PANEL_WEB_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "3x-ui 面板公网路径 / webBasePath（必须和面板 url 根路径一致）" "3x-ui public panel path / webBasePath (must match the panel URL root path)" "Публичный путь панели 3x-ui / webBasePath (должен совпадать с корневым URL панели)")" "$default_panel_path")")
    SUB_LISTEN_PORT=$(ask_with_default "$(localized_text "3x-ui 订阅服务端口（可自定义）" "3x-ui Subscription service port (customizable)" "3x-ui Порт службы подписки (настраиваемый)")" "$default_sub_port")
    SUB_URI_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "3x-ui 普通订阅路径前缀（不带端口和客户端 Subscription，建议写 /sub/）" "3x-ui standard subscription path prefix (without port or client identifier; recommended: /sub/)" "Префикс обычной подписки 3x-ui (без порта и идентификатора клиента; рекомендуется /sub/)")" "$default_sub_path")")
    CLASH_URI_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "3x-ui Clash/Mihomo 订阅路径前缀（不带客户端 Subscription，建议写 /clash/）" "3x-ui Clash/Mihomo subscription path prefix (without client identifier; recommended: /clash/)" "Префикс подписки Clash/Mihomo в 3x-ui (без идентификатора клиента; рекомендуется /clash/)")" "$default_clash_path")")
    local panel_whitelist_enabled panel_whitelist_input panel_whitelist_ranges current_client_ip
    local -a panel_whitelist_array=()
    read_trimmed panel_whitelist_enabled "$(localized_text "是否为面板域名启用 IP 白名单？(Y/n，默认 y): " "Enable IP whitelisting for panel domains? (Y/n, default y):" "Включить белый список IP-адресов для доменных имен панели? (Да/нет, по умолчанию y):")"
    if is_yes "$panel_whitelist_enabled"; then
        if ! web_proxy_engine_supports_web_whitelist "${ENTRY_MODE:-nginx-stream}" "$WEB_PROXY_ENGINE"; then
            echo -e "$(localized_text "${RED}❌ xray-fallback 模式不支持 Web 白名单。${PLAIN}" "${RED}❌ xray-fallback mode does not support web whitelisting.${PLAIN}" "${RED}❌ Резервный режим xray не поддерживает белый список веб-сайтов.${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}请改用 Nginx Stream/TCP Peek 入口模式。${PLAIN}" "${YELLOW}For , please use Nginx Stream/TCP Peek entry mode instead.${PLAIN}" "${YELLOW}Для вместо этого используйте режим ввода Nginx Stream/TCP Peek.${PLAIN}")"
            return 1
        fi
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
            if is_yes "$advanced_mode"; then
                SITE_BACKEND_ADDRS[$i]=$(ask_with_default "$(localized_text "网站 ${SITE_DOMAINS[$i]} 的后端地址" "The backend address of the website ${SITE_DOMAINS[$i]}" "Внутренний адрес сайта ${SITE_DOMAINS[$i]}")" "127.0.0.1")
            else
                SITE_BACKEND_ADDRS[$i]="127.0.0.1"
            fi
            SITE_BACKEND_PORTS[$i]=$(ask_with_default "$(localized_text "网站 ${SITE_DOMAINS[$i]} 的后端端口" "Backend port of website ${SITE_DOMAINS[$i]}" "Внутренний порт веб-сайта ${SITE_DOMAINS[$i]}")" "$default_site_port")
            default_site_port=$((default_site_port + 1))
        done
    fi

    echo -e "$(localized_text "${YELLOW}443端口复用需要 3x-ui 面板/订阅后端使用 HTTP，由 $(web_proxy_engine_label "$WEB_PROXY_ENGINE") 统一托管公网证书。${PLAIN}" "${YELLOW}Port 443 Reuse requires the 3x-ui panel/subscription backend to use HTTP, which will centrally manage the public certificate.${PLAIN}" "${YELLOW}Для повторного использования порта 443 требуется, чтобы бэкенд панели/подписки 3x-ui использовала HTTP, который будет централизованно управлять сертификатом публичной сети.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}本向导会让 $(web_proxy_engine_label "$WEB_PROXY_ENGINE") 通过 HTTP 连接 ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} 和 ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}。${PLAIN}" "${YELLOW}This wizard will allow $(web_proxy_engine_label \"$WEB_PROXY_ENGINE\") to connect ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} and ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT} through HTTP.${PLAIN}" "${YELLOW}Этот мастер позволит $(web_proxy_engine_label \"$WEB_PROXY_ENGINE\") соединить ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} и ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT} через HTTP.${PLAIN}")"
    echo -e "$(localized_text "${CYAN}证书处理分两种情况：${PLAIN}" "${CYAN}Certificate processing is divided into two situations:${PLAIN}" "${CYAN}Обработка сертификата делится на две ситуации:.${PLAIN}")"
    echo -e "$(localized_text "  3x-ui 3.x 新安装：在官方安装器选第 4 项 Skip SSL，再选 y 仅绑定 127.0.0.1；本步骤只做兜底检查。" "  New 3x-ui 3.x installation: choose option 4, Skip SSL, then enter y to bind only to 127.0.0.1. This step is only a fallback check." "  Новая установка 3x-ui 3.x: выберите пункт 4 Skip SSL, затем введите y для привязки только к 127.0.0.1. Этот шаг выполняет только проверку.")"
    echo -e "$(localized_text "  3x-ui 2.x、升级旧配置、或曾经启用过 3x-ui SSL：继续按旧流程清空面板/订阅证书路径。" "3x-ui 2.x, upgrading old configuration, or 3x-ui SSL has been enabled: Continue to clear the panel/subscription certificate path according to the old process." "3x-ui 2.x, обновление старой конфигурации или 3x-ui SSL включен: продолжайте очищать путь сертификата панели/подписки в соответствии со старым процессом.")"
    local cert_clear_confirm
    read_trimmed cert_clear_confirm "$(localized_text "是否现在兜底清空 2.x/旧配置中的 3x-ui 面板/订阅证书路径？(Y/n，默认 yes): " "Do you want to clean up the 3x-ui panel/subscription certificate path in the 2.x/old configuration now? (Y/n, default yes):" "Хотите ли вы сейчас очистить путь к сертификату панели/подписки 3x-ui в конфигурации 2.x/old? (Да/нет, по умолчанию да):")"
    cert_clear_confirm="${cert_clear_confirm:-yes}"
    if is_yes "$cert_clear_confirm"; then
        if ! clear_xui_cert_settings_for_single_443; then
            read_trimmed cert_clear_confirm "$(localized_text "未能自动确认清空，是否已经手动清空面板证书和订阅证书路径？(Y/n，默认 y): " "Failed to automatically confirm the clearing. Have you manually cleared the panel certificate and subscription certificate paths? (Y/n, default y):" "Не удалось автоматически подтвердить очистку. Очистили ли вы вручную пути к сертификату панели и сертификату подписки? (Да/нет, по умолчанию y):")"
            is_yes "$cert_clear_confirm" || { echo -e "$(localized_text "${YELLOW}请先回 3x-ui 清空证书路径并保存重启，再运行本向导。${PLAIN}" "${YELLOW}Please return to 3x-ui to clear the certificate path, save and restart, and then run this wizard.${PLAIN}" "${YELLOW}Вернитесь в 3x-ui, чтобы очистить путь к сертификату, сохраните его и перезапустите, а затем запустите этот мастер.${PLAIN}")"; return 1; }
        fi
    else
        read_trimmed cert_clear_confirm "$(localized_text "确认已经手动清空面板证书和订阅证书路径？(Y/n，默认 y): " "Are you sure you have manually cleared the panel certificate and subscription certificate paths? (Y/n, default y):" "Вы уверены, что вручную очистили пути к сертификатам панели и сертификатам подписки? (Да/нет, по умолчанию y):")"
        is_yes "$cert_clear_confirm" || { echo -e "$(localized_text "${YELLOW}请先回 3x-ui 清空证书路径并保存重启，再运行本向导。${PLAIN}" "${YELLOW}Please return to 3x-ui to clear the certificate path, save and restart, and then run this wizard.${PLAIN}" "${YELLOW}Вернитесь в 3x-ui, чтобы очистить путь к сертификату, сохраните его и перезапустите, а затем запустите этот мастер.${PLAIN}")"; return 1; }
    fi

    echo -e "$(localized_text "${CYAN}请输入 Cloudflare API Token（需 Zone.DNS.Edit + Zone.Zone.Read）${PLAIN}" "${CYAN}Please enter Cloudflare API Token (requires Zone.DNS.Edit + Zone.Zone.Read)${PLAIN}" "${CYAN}Введите токен API Cloudflare (требуется Zone.DNS.Edit + Zone.Zone.Read)${PLAIN}")"
    read_secret_trimmed CF_TOKEN "CF Token: "

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

    warn_if_public_bind "$(web_proxy_engine_label "$WEB_PROXY_ENGINE")" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    warn_if_public_bind "$(localized_text "3x-ui 面板" "3x-ui panel" "Панель 3x-ui")" "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT" || return 1
    warn_if_public_bind "$(localized_text "3x-ui 订阅服务" "3x-ui Subscription Service" "Служба подписки 3x-ui")" "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT" || return 1
    for site_idx in "${!SITE_DOMAINS[@]}"; do
        [[ -n "${SITE_DOMAINS[$site_idx]}" ]] || continue
        confirm_backend_target_or_continue "$(localized_text "网站/反代后端 ${SITE_DOMAINS[$site_idx]}" "Website/reverse proxy backend ${SITE_DOMAINS[$site_idx]}" "Сайт/бэкенд обратного прокси ${SITE_DOMAINS[$site_idx]}")" "${SITE_BACKEND_ADDRS[$site_idx]}" "${SITE_BACKEND_PORTS[$site_idx]}" || return 1
    done

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
    local -a whitelist_block_vars=()
    listen_directives=$(nginx_stream_listen_directives "$NGINX_LISTEN_ADDR" "$NGINX_LISTEN_PORT")
    web_backend=$(web_proxy_backend)
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")

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
    default xray_backend;
}

EOF
    if [[ ${#whitelist_block_vars[@]} -gt 0 ]]; then
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
    if [[ ${#whitelist_block_vars[@]} -gt 0 ]]; then
        cat <<'EOF' >> "$conf_file"
upstream vps_ip_reject_backend {
    server 127.0.0.1:9;
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
    local entry_mode web_proxy_engine site_domains_csv site_backend_addrs_csv site_backend_ports_csv
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
    local yn ssh_port remove_ports port
    echo -e "$(localized_text "${YELLOW}可选：防火墙只保留 SSH 与 Nginx 公网入口端口。${PLAIN}" "${YELLOW}Is optional: the firewall only reserves SSH and Nginx public entry ports.${PLAIN}" "${YELLOW}является необязательным: межсетевой экран резервирует только порты входа в публичную сеть SSH и Nginx.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}提醒：若 3x-ui 仍监听 0.0.0.0:${PANEL_LISTEN_PORT}，脚本的“自动追加当前活动端口”功能可能再次放行它。${PLAIN}" "${YELLOW}Reminder: if 3x-ui still listens on 0.0.0.0:${PANEL_LISTEN_PORT}, automatic active-port detection may allow that port again.${PLAIN}" "${YELLOW}Напоминание: если 3x-ui по-прежнему слушает 0.0.0.0:${PANEL_LISTEN_PORT}, автоматическое обнаружение активных портов может снова разрешить этот порт.${PLAIN}")"
    read_trimmed yn "$(localized_text "是否现在收紧防火墙？(Y/n，默认 y): " "Tighten the firewall now? (Y/n, default y):" "Ужесточить брандмауэр сейчас? (Да/нет, по умолчанию y):")"
    is_yes "$yn" || return 0
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
