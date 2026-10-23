# shellcheck shell=bash
# xhttp path reverse-proxy records for Web domains served by the 443 entry.

xhttp_path_mode_notice() {
    local mode
    mode=$(get_entry_mode)
    if [[ "$mode" == "xray-fallback" ]]; then
        echo -e "$(localized_text "${RED}❌ xray-fallback 模式下 Xray 主入站独占公网 443，本菜单不可用。${PLAIN}" "${RED}❌ In xray-fallback mode the Xray main inbound owns public port 443, so this menu is unavailable.${PLAIN}" "${RED}❌ В режиме xray-fallback основной вход Xray занимает публичный порт 443, поэтому это меню недоступно.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}需要 XHTTP 共用 Web 域名时，请切到 nginx-stream 或 tcp-peek。${PLAIN}" "${YELLOW}Switch to nginx-stream or tcp-peek to share a Web domain with XHTTP.${PLAIN}" "${YELLOW}Чтобы использовать общий Web-домен для XHTTP, переключитесь на nginx-stream или tcp-peek.${PLAIN}")"
        return 0
    fi
    return 1
}

list_xhttp_path_routes() {
    load_sni_stack_env || return 1
    local i num owner ranges
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}XHTTP 节点路径反代${PLAIN}" "${BOLD}XHTTP node path reverse proxy${PLAIN}" "${BOLD}Обратный прокси пути узла XHTTP${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "配置文件：$(xhttp_paths_path)" "Configuration file: $(xhttp_paths_path)" "Файл конфигурации: $(xhttp_paths_path)")"
    echo -e "$(localized_text "规则格式：域名|路径|本地地址|本地端口" "Rule format: DOMAIN|PATH|ADDR|PORT" "Формат правила: DOMAIN|PATH|ADDR|PORT")"
    echo -e "$(localized_text "${YELLOW}TLS 由本地 Web 反代引擎终结；本地 XHTTP 入站必须不启用 TLS。${PLAIN}" "${YELLOW}TLS terminates on the local Web proxy; the local XHTTP inbound must run without TLS.${PLAIN}" "${YELLOW}TLS завершается на локальном Web-прокси; локальный вход XHTTP должен работать без TLS.${PLAIN}")"
    echo -e "------------------------------------------------"
    if [[ ${#XHTTP_PATH_DOMAINS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有 XHTTP 路径反代规则。${PLAIN}" "${YELLOW}No XHTTP path reverse-proxy rules currently.${PLAIN}" "${YELLOW}Правил обратного прокси пути XHTTP нет.${PLAIN}")"
        return 0
    fi
    for i in "${!XHTTP_PATH_DOMAINS[@]}"; do
        num=$((i + 1))
        if [[ "${XHTTP_PATH_DOMAINS[$i]}" == "$PANEL_DOMAIN" ]]; then
            owner="$(localized_text "面板域名" "panel domain" "домен панели")"
        else
            owner="$(localized_text "Web 域名" "Web domain" "Web-домен")"
        fi
        echo -e "${GREEN}${num}.${PLAIN} https://${XHTTP_PATH_DOMAINS[$i]}${XHTTP_PATH_PATHS[$i]} -> ${XHTTP_PATH_ADDRS[$i]}:${XHTTP_PATH_PORTS[$i]} ${CYAN}[${owner}]${PLAIN}"
        ranges=$(sni_ip_whitelist_ranges_for_domain "${XHTTP_PATH_DOMAINS[$i]}")
        if [[ -n "$ranges" ]]; then
            echo -e "$(localized_text "    ${YELLOW}该域名启用了 Web 白名单，XHTTP 流量同样受限：${ranges}${PLAIN}" "    ${YELLOW}This domain has a Web whitelist, so XHTTP traffic is limited too: ${ranges}${PLAIN}" "    ${YELLOW}Для этого домена включён белый список, XHTTP тоже ограничен: ${ranges}${PLAIN}")"
        fi
    done
}

add_xhttp_path_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}添加 XHTTP 路径反代${PLAIN}" "${BOLD}Add an XHTTP path reverse proxy${PLAIN}" "${BOLD}Добавить обратный прокси пути XHTTP${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    xhttp_path_mode_notice && return 0

    local -a domains=("$PANEL_DOMAIN")
    local site_domain
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ -n "$site_domain" ]] && domains+=("$site_domain")
    done

    echo -e "$(localized_text "${YELLOW}先在 3x-ui 创建并启用 VLESS + XHTTP 入站：监听 127.0.0.1，本地端口自定，security 和 decryption 选 none，flow 与 Host 留空，mode 选 auto，path 与下面一致。${PLAIN}" "${YELLOW}First create and enable a VLESS + XHTTP inbound in 3x-ui: listen on 127.0.0.1, pick a local port, set security and decryption to none, leave flow and Host empty, set mode to auto, and match the path below.${PLAIN}" "${YELLOW}Сначала создайте и включите вход VLESS + XHTTP в 3x-ui: адрес 127.0.0.1, свободный порт, security и decryption = none, flow и Host пустые, mode = auto, путь как ниже.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}这里只登记 域名 + 路径 -> 本地地址:端口；证书和 TLS 由本地 Web 反代引擎处理。客户端 mode 先选 packet-up。${PLAIN}" "${YELLOW}This menu only records DOMAIN + PATH -> local address:port; certificates and TLS stay on the local Web proxy. Start with client mode packet-up.${PLAIN}" "${YELLOW}Здесь задаётся только DOMAIN + PATH -> локальный адрес:порт; сертификат и TLS остаются на Web-прокси. Начните с mode = packet-up в клиенте.${PLAIN}")"
    echo -e "------------------------------------------------"

    local i choice idx domain path_input route_path conflict addr port listen_line
    for i in "${!domains[@]}"; do
        echo -e "${GREEN}$((i + 1)).${PLAIN} ${domains[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "$(localized_text "选择承载 XHTTP 的 Web 域名序号: " "Select the Web domain that will carry XHTTP: " "Выберите Web-домен для XHTTP: ")"
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消添加。${PLAIN}" "${BLUE}Add cancelled.${PLAIN}" "${BLUE}Добавление отменено.${PLAIN}")"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#domains[@]} )); then
        echo -e "$(localized_text "${RED}❌ 序号无效。${PLAIN}" "${RED}❌ The serial number is invalid.${PLAIN}" "${RED}❌ Серийный номер недействителен.${PLAIN}")"
        return 1
    fi
    idx=$((choice - 1))
    domain="${domains[$idx]}"

    read_trimmed path_input "$(localized_text "XHTTP 路径（示例值 /xxx；须与 3x-ui 入站 path 一致，不带域名）: " "XHTTP path (example: /xxx; must match the 3x-ui inbound path, no host): " "Путь XHTTP (пример: /xxx; должен совпадать с path входа 3x-ui, без домена): ")"
    route_path=$(normalize_xhttp_path "$path_input" 2>/dev/null || true)
    if [[ -z "$route_path" ]]; then
        echo -e "$(localized_text "${RED}❌ 路径无效：必须是以 / 开头的单一前缀，不能是 /，也不能包含空格、?、# 或 ..。${PLAIN}" "${RED}❌ Invalid path: use a single prefix starting with /, not /, without spaces, ?, # or ...${PLAIN}" "${RED}❌ Неверный путь: нужен префикс с /, не /, без пробелов, ?, # и ...${PLAIN}")"
        return 1
    fi
    conflict=$(xhttp_path_conflicts_with_web_paths "$route_path" || true)
    if [[ -n "$conflict" ]]; then
        echo -e "$(localized_text "${RED}❌ 路径 ${route_path} 与面板/订阅路径 ${conflict} 冲突。${PLAIN}" "${RED}❌ Path ${route_path} conflicts with the panel/subscription path ${conflict}.${PLAIN}" "${RED}❌ Путь ${route_path} конфликтует с путём панели/подписки ${conflict}.${PLAIN}")"
        return 1
    fi
    for i in "${!XHTTP_PATH_DOMAINS[@]}"; do
        if [[ "${XHTTP_PATH_DOMAINS[$i]}" == "$domain" && "${XHTTP_PATH_PATHS[$i]}" == "$route_path" ]]; then
            echo -e "$(localized_text "${RED}❌ ${domain}${route_path} 已存在相同的 XHTTP 路径规则。${PLAIN}" "${RED}❌ ${domain}${route_path} already has an XHTTP path rule.${PLAIN}" "${RED}❌ Для ${domain}${route_path} уже есть правило XHTTP.${PLAIN}")"
            return 1
        fi
    done

    addr=$(ask_with_default "$(localized_text "本地监听地址" "local listening address" "локальный адрес прослушивания")" "127.0.0.1")
    addr=$(normalize_loopback_addr "$addr")
    port=$(ask_with_default "$(localized_text "已有 XHTTP 入站的本地端口（示例值 2400，以 3x-ui 为准）" "Existing XHTTP inbound local port (example: 2400; match 3x-ui)" "Локальный порт существующего входа XHTTP (пример: 2400; как в 3x-ui)")" "2400")
    is_loopback_listen_addr "$addr" || { echo -e "$(localized_text "${RED}❌ 本地监听地址只允许 127.0.0.1、localhost 或 ::1。${PLAIN}" "${RED}❌ The local listening address must be 127.0.0.1, localhost or ::1.${PLAIN}" "${RED}❌ Локальный адрес должен быть 127.0.0.1, localhost или ::1.${PLAIN}")"; return 1; }
    is_valid_port "$port" || { echo -e "$(localized_text "${RED}❌ 本地监听端口无效：${port}${PLAIN}" "${RED}❌ Invalid local listening port: ${port}${PLAIN}" "${RED}❌ Неверный локальный порт: ${port}${PLAIN}")"; return 1; }
    if [[ "$port" == "$NGINX_LISTEN_PORT" || "$port" == "$CADDY_LISTEN_PORT" || "$port" == "$PANEL_LISTEN_PORT" || "$port" == "$SUB_LISTEN_PORT" ]]; then
        echo -e "$(localized_text "${RED}❌ 该端口与公网入口、Web 反代、面板或订阅端口冲突。${PLAIN}" "${RED}❌ This port conflicts with the public entry, Web proxy, panel or subscription port.${PLAIN}" "${RED}❌ Порт конфликтует с публичным входом, Web-прокси, панелью или подпиской.${PLAIN}")"
        return 1
    fi

    print_xray_route_port_status "$domain" "$addr" "$port"
    listen_line=$(xray_route_listen_line_by_addr_port "$addr" "$port")
    if [[ -z "$listen_line" ]]; then
        echo -e "$(localized_text "${RED}❌ 端口未监听，请先去 3x-ui 创建并启用对应 XHTTP 入站。${PLAIN}" "${RED}❌ The port is not listening. Create and enable the XHTTP inbound in 3x-ui first.${PLAIN}" "${RED}❌ Порт не прослушивается. Сначала создайте и включите вход XHTTP в 3x-ui.${PLAIN}")"
        return 1
    fi
    confirm_non_xray_route_listener "$listen_line" || return 0

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${CYAN}即将添加：https://${domain}${route_path} -> ${addr}:${port}${PLAIN}" "${CYAN}Will be added: https://${domain}${route_path} -> ${addr}:${port}${PLAIN}" "${CYAN}Будет добавлено: https://${domain}${route_path} -> ${addr}:${port}${PLAIN}")"
    confirm_risk_action \
        "$(localized_text "添加 XHTTP 路径反代 ${domain}${route_path}" "Add the XHTTP path reverse proxy ${domain}${route_path}" "Добавить обратный прокси пути XHTTP ${domain}${route_path}")" \
        "$(localized_text "重新渲染 Web 反代配置；本地 ${addr}:${port} 会通过 ${domain} 的 443 对外提供 XHTTP" "regenerate the Web proxy configuration; local ${addr}:${port} will serve XHTTP through ${domain} on port 443" "пересоздать конфигурацию Web-прокси; локальный ${addr}:${port} будет отдавать XHTTP через ${domain} на порту 443")" \
        "$(localized_text "从本菜单删除该规则并重新应用" "remove the rule from this menu and reapply" "удалить правило в этом меню и применить заново")" \
        "$(localized_text "确认 3x-ui 入站的 path 与 ${route_path} 完全一致，且该入站没有启用 TLS。" "Confirm the 3x-ui inbound path is exactly ${route_path} and TLS is disabled on that inbound." "Убедитесь, что path входа 3x-ui совпадает с ${route_path}, а TLS отключён.")" || return 0

    idx=${#XHTTP_PATH_DOMAINS[@]}
    XHTTP_PATH_DOMAINS[$idx]="$domain"
    XHTTP_PATH_PATHS[$idx]="$route_path"
    XHTTP_PATH_ADDRS[$idx]="$addr"
    XHTTP_PATH_PORTS[$idx]="$port"
    save_and_offer_reapply_sni_stack || return 1
    echo -e "$(localized_text "${GREEN}✅ 已保存 XHTTP 路径反代：https://${domain}${route_path} -> ${addr}:${port}${PLAIN}" "${GREEN}✅ Saved XHTTP path reverse proxy: https://${domain}${route_path} -> ${addr}:${port}${PLAIN}" "${GREEN}✅ Сохранён обратный прокси пути XHTTP: https://${domain}${route_path} -> ${addr}:${port}${PLAIN}")"
}

remove_xhttp_path_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}删除 XHTTP 路径反代${PLAIN}" "${BOLD}Remove an XHTTP path reverse proxy${PLAIN}" "${BOLD}Удалить обратный прокси пути XHTTP${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    xhttp_path_mode_notice && return 0
    if [[ ${#XHTTP_PATH_DOMAINS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有可删除的 XHTTP 路径反代规则。${PLAIN}" "${YELLOW}No XHTTP path reverse-proxy rules can be removed.${PLAIN}" "${YELLOW}Нет правил обратного прокси пути XHTTP для удаления.${PLAIN}")"
        return 0
    fi

    local i num choice idx domain route_path
    local -a new_domains=() new_paths=() new_addrs=() new_ports=()
    for i in "${!XHTTP_PATH_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} https://${XHTTP_PATH_DOMAINS[$i]}${XHTTP_PATH_PATHS[$i]} -> ${XHTTP_PATH_ADDRS[$i]}:${XHTTP_PATH_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "$(localized_text "请输入要删除的序号: " "Please enter the serial number to be removed:" "Введите номер для удаления:")"
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消删除。${PLAIN}" "${BLUE}Removal cancelled.${PLAIN}" "${BLUE}Удаление отменено.${PLAIN}")"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#XHTTP_PATH_DOMAINS[@]} )); then
        echo -e "$(localized_text "${RED}❌ 序号无效。${PLAIN}" "${RED}❌ The serial number is invalid.${PLAIN}" "${RED}❌ Серийный номер недействителен.${PLAIN}")"
        return 1
    fi

    idx=$((choice - 1))
    domain="${XHTTP_PATH_DOMAINS[$idx]}"
    route_path="${XHTTP_PATH_PATHS[$idx]}"
    confirm_risk_action \
        "$(localized_text "删除 XHTTP 路径反代 ${domain}${route_path}" "Remove the XHTTP path reverse proxy ${domain}${route_path}" "Удалить обратный прокси пути XHTTP ${domain}${route_path}")" \
        "$(localized_text "重新渲染 Web 反代配置；该路径会回落到域名默认后端" "regenerate the Web proxy configuration; the path falls back to the domain default backend" "пересоздать конфигурацию Web-прокси; путь вернётся к бэкенду домена по умолчанию")" \
        "$(localized_text "重新添加相同的域名、路径和本地端口" "add the same domain, path, and local port again" "снова добавить тот же домен, путь и локальный порт")" || return 0
    for i in "${!XHTTP_PATH_DOMAINS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_domains+=("${XHTTP_PATH_DOMAINS[$i]}")
        new_paths+=("${XHTTP_PATH_PATHS[$i]}")
        new_addrs+=("${XHTTP_PATH_ADDRS[$i]}")
        new_ports+=("${XHTTP_PATH_PORTS[$i]}")
    done
    XHTTP_PATH_DOMAINS=("${new_domains[@]}")
    XHTTP_PATH_PATHS=("${new_paths[@]}")
    XHTTP_PATH_ADDRS=("${new_addrs[@]}")
    XHTTP_PATH_PORTS=("${new_ports[@]}")
    save_and_offer_reapply_sni_stack || return 1
    echo -e "$(localized_text "${GREEN}✅ 已删除 XHTTP 路径反代：${domain}${route_path}${PLAIN}" "${GREEN}✅ Removed XHTTP path reverse proxy: ${domain}${route_path}${PLAIN}" "${GREEN}✅ Удалён обратный прокси пути XHTTP: ${domain}${route_path}${PLAIN}")"
}

manage_xhttp_path_routes() {
    load_sni_stack_env || return 1
    xhttp_path_mode_notice && { pause_return; return 0; }

    while true; do
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}XHTTP 节点路径反代${PLAIN}" "${BOLD}XHTTP node path reverse proxy${PLAIN}" "${BOLD}Обратный прокси пути узла XHTTP${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}让 XHTTP 节点与面板/网站共用同一个 443 和同一个域名，按路径分流；TLS 由本地 Web 反代引擎终结。${PLAIN}" "${YELLOW}Share one port 443 and one domain between XHTTP nodes and the panel/site, routed by path; TLS terminates on the local Web proxy.${PLAIN}" "${YELLOW}XHTTP и панель/сайт используют один порт 443 и один домен, разделение по пути; TLS завершается на локальном Web-прокси.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}只管理路径反代记录，不创建或修改 3x-ui/Xray 入站。${PLAIN}" "${YELLOW}Only manages path reverse-proxy records; does not create or edit 3x-ui/Xray inbounds.${PLAIN}" "${YELLOW}Управляет только записями обратного прокси; входы 3x-ui/Xray не создаются и не изменяются.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}CDN：先直连验证，再启用 HTTPS 回源和路径缓存绕过；Web 白名单看到的是 CDN 回源 IP。${PLAIN}" "${YELLOW}CDN: verify directly first, then use HTTPS to the origin and bypass cache for the path; Web allowlists see CDN origin-facing IPs.${PLAIN}" "${YELLOW}CDN: сначала проверьте прямое подключение, затем включите HTTPS до сервера и обход кэша пути; Web-список видит IP CDN.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}上下行分离：两个 Web 域名的同一路径指向同一入站，Host 留空；客户端用 downloadSettings 指定下行。${PLAIN}" "${YELLOW}Split upload/download: route the same path on two Web domains to one inbound, leave inbound Host empty, and set client downloadSettings for downloads.${PLAIN}" "${YELLOW}Разделение направлений: одинаковый путь двух Web-доменов ведёт на один вход с пустым Host; downloadSettings клиента задаёт скачивание.${PLAIN}")"
        echo -e "$(localized_text "配置文件：$(xhttp_paths_path)" "Configuration file: $(xhttp_paths_path)" "Файл конфигурации: $(xhttp_paths_path)")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 查看 XHTTP 路径规则${PLAIN}" "${GREEN}  1. View XHTTP path rules${PLAIN}" "${GREEN}  1. Показать правила пути XHTTP${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 添加 XHTTP 路径规则${PLAIN}" "${GREEN}  2. Add an XHTTP path rule${PLAIN}" "${GREEN}  2. Добавить правило пути XHTTP${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 删除 XHTTP 路径规则${PLAIN}" "${GREEN}  3. Remove an XHTTP path rule${PLAIN}" "${GREEN}  3. Удалить правило пути XHTTP${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
        case "$choice" in
            1) list_xhttp_path_routes ;;
            2) add_xhttp_path_route ;;
            3) remove_xhttp_path_route ;;
            0|q|Q|'') break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"; continue ;;
        esac
        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}
