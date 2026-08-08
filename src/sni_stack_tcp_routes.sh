# shellcheck shell=bash
# 443 stack custom TCP-route CRUD workflows.

list_sni_stack_tcp_routes() {
    load_sni_stack_env || return 1
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}当前 443 TCP/SNI 本地入站分流${PLAIN}" "${BOLD}Current 443 TCP/SNI local inbound offload${PLAIN}" "${BOLD}текущий 443 TCP/SNI локальная входящая разгрузка${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "公网入口：${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT}" "public entry: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT}" "Вход в публичную сеть: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT}.")"
    echo -e "$(localized_text "REALITY 默认后端：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}" "REALITY Default backend: ${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}" "REALITY бэкенд по умолчанию: ${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}")"
    echo -e "------------------------------------------------"
    if [[ ${#TCP_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有额外 TCP/SNI 入站分流。${PLAIN}" "${YELLOW}Currently has no additional TCP/SNI inbound offload.${PLAIN}" "${YELLOW}в настоящее время не имеет дополнительной входящей разгрузки TCP/SNI.${PLAIN}")"
        return 0
    fi

    local i num
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${TCP_ROUTE_SNIS[$i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$i]}:${TCP_ROUTE_PORTS[$i]}"
    done
}

add_sni_stack_tcp_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}新增 443 TCP/SNI 本地入站分流${PLAIN}" "${BOLD}Added 443 TCP/SNI local inbound offload${PLAIN}" "${BOLD}добавлено 443 TCP/SNI локальная входящая разгрузка${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "$(localized_text "${YELLOW}用途：你已在 3x-ui 新增本地入站，本功能只把某个 SNI 通过公网 ${NGINX_LISTEN_PORT} 分流到该本地端口。${PLAIN}" "${YELLOW}Purpose: You have added a local inbound port in 3x-ui. This function only distributes a certain SNI to the local port through the public ${NGINX_LISTEN_PORT}.${PLAIN}" "${YELLOW}Назначение: вы добавили локальное входящее соединение в 3x-ui. Эта функция направляет только определенный SNI на локальный порт через Интернет ${NGINX_LISTEN_PORT}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}要求：协议必须是 TCP 且客户端握手能带 SNI；UDP/QUIC/Hysteria2/TUIC 或无 SNI 的裸协议不适用。${PLAIN}" "${YELLOW}Requirements: The protocol must be TCP and the client handshake can carry SNI; UDP/QUIC/Hysteria2/TUIC or bare protocols without SNI are not applicable.${PLAIN}" "${YELLOW}Требования : протокол должен быть TCP, а подтверждение связи клиента может передавать SNI; UDP/QUIC/Hysteria2/TUIC или простые протоколы без SNI неприменимы.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}安全边界：后端只允许 127.0.0.1/localhost/::1，不会开放新公网端口。${PLAIN}" "${YELLOW}Security boundary: The backend only allows 127.0.0.1/localhost/::1 and will not open new public ports.${PLAIN}" "${YELLOW}Граница безопасности : бэкенд разрешает только 127.0.0.1/localhost/::1 и не открывает новые порты публичной сети.${PLAIN}")"
    echo -e "------------------------------------------------"

    local route_sni route_addr route_port existing idx
    read_trimmed route_sni "$(localized_text "请输入用于分流的新 SNI/域名（例如 relay.example.com）: " "Please enter the new SNI/domain to be used for offloading (e.g. relay.example.com):" "Введите новое SNI/имя домена, которое будет использоваться для разгрузки (например, relay.example.com):")"
    route_sni=$(normalize_domain_input "$route_sni")
    if [[ -z "$route_sni" || "$route_sni" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消新增 TCP/SNI 入站。${PLAIN}" "${BLUE}Canceled the addition of TCP/SNI.${PLAIN}" "${BLUE}отменил добавление TCP/SNI.${PLAIN}")"
        return 0
    fi
    is_valid_domain "$route_sni" || { echo -e "$(localized_text "${RED}❌ SNI/域名格式无效。${PLAIN}" "${RED}❌ SNI/The domain format is invalid.${PLAIN}" "${RED}❌ SNI/Неверный формат доменного имени.${PLAIN}")"; return 1; }
    if [[ "$route_sni" == "$PANEL_DOMAIN" || "$route_sni" == "$REALITY_SNI" ]]; then
        echo -e "$(localized_text "${RED}❌ TCP/SNI 入站域名不能和面板域名或 REALITY SNI 相同。${PLAIN}" "${RED}❌ The TCP/SNI inbound domain cannot be the same as the panel domain or REALITY SNI.${PLAIN}" "${RED}❌ Имя входящего домена TCP/SNI не может совпадать с именем домена панели или REALITY SNI.${PLAIN}")"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 该域名已作为网站/反代域名使用。${PLAIN}" "${RED}❌ This domain has been used as a website/reverse proxy domain.${PLAIN}" "${RED}❌ Это доменное имя использовалось в качестве доменного имени веб-сайта/обратного прокси-сервера.${PLAIN}")"; return 1; }
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 该 TCP/SNI 入站已经存在。${PLAIN}" "${RED}❌ The TCP/SNI inbound already exists.${PLAIN}" "${RED}❌ входящее подключение TCP/SNI уже существует.${PLAIN}")"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 该域名已作为 Xray 入站使用。${PLAIN}" "${RED}❌ This domain has been used inbound as Xray.${PLAIN}" "${RED}❌ Это доменное имя использовалось в качестве Xray.${PLAIN}")"; return 1; }
    done

    check_domain_dns_sanity "$route_sni" "$(localized_text "TCP/SNI 入站域名" "TCP/SNI inbound domain" "TCP/SNI имя входящего домена")" "warn" || echo -e "$(localized_text "${YELLOW}⚠️ 如果客户端使用服务器 IP 连接并手动指定 SNI，可忽略该 DNS 警告。${PLAIN}" "${YELLOW}⚠️ This DNS warning can be ignored if the client connects using the server IP and manually specifies SNI.${PLAIN}" "${YELLOW}⚠️ Это предупреждение DNS можно игнорировать, если клиент подключается с использованием IP-адреса сервера и вручную указывает SNI.${PLAIN}")"
    route_addr=$(ask_with_default "$(localized_text "3x-ui 新入站本地监听地址（只允许本地）" "3x-ui New inbound local listening address (only local)" "3x-ui Новый входящий локальный адрес прослушивания (только локальный)")" "127.0.0.1")
    route_addr=$(normalize_loopback_addr "$route_addr")
    route_port=$(ask_with_default "$(localized_text "3x-ui 新入站本地监听端口" "3x-ui New inbound local listening port" "3x-ui Новый входящий локальный порт прослушивания")" "8443")
    is_loopback_listen_addr "$route_addr" || { echo -e "$(localized_text "${RED}❌ 为保证安全，TCP/SNI 入站后端只允许 127.0.0.1、localhost 或 ::1。${PLAIN}" "${RED}❌ To ensure security, the TCP/SNI inbound backend only allows 127.0.0.1, localhost or ::1.${PLAIN}" "${RED}❌ В целях обеспечения безопасности входящий сервер TCP/SNI допускает только 127.0.0.1, localhost или ::1.${PLAIN}")"; return 1; }
    is_valid_port "$route_port" || { echo -e "$(localized_text "${RED}❌ 入站端口无效：${route_port}${PLAIN}" "${RED}❌ Invalid inbound port: ${route_port}${PLAIN}" "${RED}❌ Неверный входящий порт: ${route_port}.${PLAIN}")"; return 1; }
    if [[ "$route_port" == "$NGINX_LISTEN_PORT" || "$route_port" == "$CADDY_LISTEN_PORT" || "$route_port" == "$PANEL_LISTEN_PORT" || "$route_port" == "$SUB_LISTEN_PORT" ]]; then
        echo -e "$(localized_text "${RED}❌ 入站端口不能复用公网入口、Caddy、面板或订阅服务端口。${PLAIN}" "${RED}❌ The inbound port cannot reuse the public entry, Caddy, panel or subscription service port.${PLAIN}" "${RED}❌ Входящий порт не может повторно использовать вход в публичную сеть, Caddy, порт панели или сервисный порт подписки.${PLAIN}")"
        return 1
    fi

    echo -e ""
    echo -e "$(localized_text "${CYAN}即将添加 TCP/SNI 分流：${route_sni}:${NGINX_LISTEN_PORT} -> ${route_addr}:${route_port}${PLAIN}" "${CYAN}Will be added soon. TCP/SNI routing: ${route_sni}:${NGINX_LISTEN_PORT} -> ${route_addr}:${route_port}${PLAIN}" "${CYAN}будет добавлен в ближайшее время. TCP/SNI маршрутизация: ${route_sni}:${NGINX_LISTEN_PORT} -> ${route_addr}:${route_port}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}请确认 3x-ui 入站已监听 ${route_addr}:${route_port}，且客户端连接端口使用 ${NGINX_LISTEN_PORT}。${PLAIN}" "${YELLOW}Please confirm that 3x-ui inbound is listening to ${route_addr}:${route_port}, and the client connection port uses ${NGINX_LISTEN_PORT}.${PLAIN}" "${YELLOW}Подтвердите, что 3x-ui прослушивает входящее подключение ${route_addr}:${route_port}, а порт подключения клиента использует ${NGINX_LISTEN_PORT}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}说明：Web 白名单只保护 Web 域名，不会应用到 TCP/SNI 或 Xray 节点流量。${PLAIN}" "${YELLOW}Note: The Web whitelist only protects Web domains and will not be applied to TCP/SNI or Xray node traffic.${PLAIN}" "${YELLOW}Примечание. Белый список веб-сайтов защищает только имена веб-доменов и не будет применяться к трафику узлов TCP/SNI или Xray.${PLAIN}")"
    confirm_risk_action "$(localized_text "新增 443 TCP/SNI 入站 ${route_sni}" "Added 443 TCP/SNI inbound ${route_sni}" "Добавлен 443 TCP/SNI входящий ${route_sni}.")" \
        "$(localized_text "Nginx stream SNI 分流规则，会把该 SNI 直通到本地 3x-ui 入站" "Nginx stream SNI routing rule will pass the SNI directly to the local 3x-ui inbound connection" "Правило маршрутизации Nginx stream SNI передаст SNI непосредственно локальному входящему соединению 3x-ui.")" \
        "$(localized_text "使用 443 单入口备份恢复，或从 TCP/SNI 入站管理菜单删除该分流" "Restore using a 443 share entry backup, or delete the route from the TCP/SNI inbound connection management menu" "Восстановите резервную копию общей точки входа 443 или удалите маршрут в меню управления входящими подключениями TCP/SNI.")" \
        "$(localized_text "确认后端只监听本地地址，不要在安全组或防火墙开放 ${route_port}。" "Confirm that the backend only listens to the local address and does not open ${route_port} in the security group or firewall." "Убедитесь, что бэкенд прослушивает только локальный адрес и не открывает ${route_port} в группе безопасности или брандмауэре.")" || return 1

    idx=${#TCP_ROUTE_SNIS[@]}
    TCP_ROUTE_SNIS[$idx]="$route_sni"
    TCP_ROUTE_ADDRS[$idx]="$route_addr"
    TCP_ROUTE_PORTS[$idx]="$route_port"
    save_and_offer_reapply_sni_stack
}

edit_sni_stack_tcp_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}修改 443 TCP/SNI 本地入站分流${PLAIN}" "${BOLD}Modification 443 TCP/SNI local inbound offload${PLAIN}" "${BOLD}модификация 443 TCP/SNI локальная входящая разгрузка${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    if [[ ${#TCP_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有可修改的 TCP/SNI 入站分流。${PLAIN}" "${YELLOW}Currently has no modifiable TCP/SNI inbound offload.${PLAIN}" "${YELLOW}в настоящее время не имеет изменяемой входящей разгрузки TCP/SNI.${PLAIN}")"
        return 0
    fi

    local i num choice idx old_sni new_sni new_addr new_port existing
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${TCP_ROUTE_SNIS[$i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$i]}:${TCP_ROUTE_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "$(localized_text "请输入要修改的序号: " "Please enter the serial number to be modified:" "Пожалуйста, введите серийный номер, который необходимо изменить:")"
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消修改。${PLAIN}" "${BLUE}Has been modified.${PLAIN}" "${BLUE}был изменен.${PLAIN}")"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#TCP_ROUTE_SNIS[@]} )); then
        echo -e "$(localized_text "${RED}❌ 序号无效。${PLAIN}" "${RED}❌ The serial number is invalid.${PLAIN}" "${RED}❌ Серийный номер недействителен.${PLAIN}")"
        return 1
    fi

    idx=$((choice - 1))
    old_sni="${TCP_ROUTE_SNIS[$idx]}"
    new_sni=$(normalize_domain_input "$(ask_with_default "$(localized_text "SNI/域名" "SNI/domain" "SNI/домен")" "$old_sni")")
    new_addr=$(ask_with_default "$(localized_text "本地监听地址（只允许本地）" "Local listening address (only local allowed)" "Локальный адрес прослушивания (разрешено только локальное)")" "${TCP_ROUTE_ADDRS[$idx]}")
    new_addr=$(normalize_loopback_addr "$new_addr")
    new_port=$(ask_with_default "$(localized_text "本地监听端口" "local listening port" "локальный порт прослушивания")" "${TCP_ROUTE_PORTS[$idx]}")

    is_valid_domain "$new_sni" || { echo -e "$(localized_text "${RED}❌ SNI/域名格式无效。${PLAIN}" "${RED}❌ SNI/The domain format is invalid.${PLAIN}" "${RED}❌ SNI/Неверный формат доменного имени.${PLAIN}")"; return 1; }
    if [[ "$new_sni" == "$PANEL_DOMAIN" || "$new_sni" == "$REALITY_SNI" ]]; then
        echo -e "$(localized_text "${RED}❌ TCP/SNI 入站域名不能和面板域名或 REALITY SNI 相同。${PLAIN}" "${RED}❌ The TCP/SNI inbound domain cannot be the same as the panel domain or REALITY SNI.${PLAIN}" "${RED}❌ Имя входящего домена TCP/SNI не может совпадать с именем домена панели или REALITY SNI.${PLAIN}")"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$new_sni" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 该域名已作为网站/反代域名使用。${PLAIN}" "${RED}❌ This domain has been used as a website/reverse proxy domain.${PLAIN}" "${RED}❌ Это доменное имя использовалось в качестве доменного имени веб-сайта/обратного прокси-сервера.${PLAIN}")"; return 1; }
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        [[ "$new_sni" == "${TCP_ROUTE_SNIS[$i]}" ]] && { echo -e "$(localized_text "${RED}❌ 该 TCP/SNI 入站已经存在。${PLAIN}" "${RED}❌ The TCP/SNI inbound already exists.${PLAIN}" "${RED}❌ входящее подключение TCP/SNI уже существует.${PLAIN}")"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$new_sni" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 该域名已作为 Xray 入站使用。${PLAIN}" "${RED}❌ This domain has been used inbound as Xray.${PLAIN}" "${RED}❌ Это доменное имя использовалось в качестве Xray.${PLAIN}")"; return 1; }
    done
    is_loopback_listen_addr "$new_addr" || { echo -e "$(localized_text "${RED}❌ 为保证安全，TCP/SNI 入站后端只允许 127.0.0.1、localhost 或 ::1。${PLAIN}" "${RED}❌ To ensure security, the TCP/SNI inbound backend only allows 127.0.0.1, localhost or ::1.${PLAIN}" "${RED}❌ В целях обеспечения безопасности входящий сервер TCP/SNI допускает только 127.0.0.1, localhost или ::1.${PLAIN}")"; return 1; }
    is_valid_port "$new_port" || { echo -e "$(localized_text "${RED}❌ 入站端口无效：${new_port}${PLAIN}" "${RED}❌ Invalid inbound port: ${new_port}${PLAIN}" "${RED}❌ Неверный входящий порт: ${new_port}.${PLAIN}")"; return 1; }
    if [[ "$new_port" == "$NGINX_LISTEN_PORT" || "$new_port" == "$CADDY_LISTEN_PORT" || "$new_port" == "$PANEL_LISTEN_PORT" || "$new_port" == "$SUB_LISTEN_PORT" ]]; then
        echo -e "$(localized_text "${RED}❌ 入站端口不能复用公网入口、Caddy、面板或订阅服务端口。${PLAIN}" "${RED}❌ The inbound port cannot reuse the public entry, Caddy, panel or subscription service port.${PLAIN}" "${RED}❌ Входящий порт не может повторно использовать вход в публичную сеть, Caddy, порт панели или сервисный порт подписки.${PLAIN}")"
        return 1
    fi

    echo -e ""
    echo -e "$(localized_text "${CYAN}即将修改：${old_sni}:${NGINX_LISTEN_PORT} -> ${new_sni}:${NGINX_LISTEN_PORT} -> ${new_addr}:${new_port}${PLAIN}" "${CYAN}Is about to be modified: ${old_sni}:${NGINX_LISTEN_PORT} -> ${new_sni}:${NGINX_LISTEN_PORT} -> ${new_addr}:${new_port}${PLAIN}" "${CYAN}скоро будет изменен: ${old_sni}:${NGINX_LISTEN_PORT} -> ${new_sni}:${NGINX_LISTEN_PORT} -> ${new_addr}:${new_port}${PLAIN}")"
    confirm_risk_action "$(localized_text "修改 443 TCP/SNI 入站 ${old_sni}" "Modify 443 TCP/SNI inbound ${old_sni}" "Изменить 443 TCP/SNI входящий ${old_sni}")" \
        "$(localized_text "Nginx stream SNI 分流规则和本地后端端口" "Nginx stream SNI Offload rules and local backend ports" "Nginx stream SNI Правила разгрузки и локальные серверные порты")" \
        "$(localized_text "使用 443 单入口备份恢复修改前配置" "Use 443 shared entry backup to restore the configuration before modification" "Используйте однократную резервную копию 443 для восстановления конфигурации до изменения.")" \
        "$(localized_text "确认 3x-ui 入站已按新地址和端口监听，且未开放该内部端口。" "Confirm that 3x-ui inbound is listening at the new address and port, and the internal port is not open." "Убедитесь, что 3x-ui прослушивает входящее подключение по новому адресу и порту, а внутренний порт не открыт.")" || return 1

    TCP_ROUTE_SNIS[$idx]="$new_sni"
    TCP_ROUTE_ADDRS[$idx]="$new_addr"
    TCP_ROUTE_PORTS[$idx]="$new_port"
    if [[ "$old_sni" != "$new_sni" ]]; then
        rename_sni_ip_whitelist_domain "$old_sni" "$new_sni"
    fi
    save_and_offer_reapply_sni_stack
}

remove_sni_stack_tcp_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}删除 443 TCP/SNI 本地入站分流${PLAIN}" "${BOLD}Deleted 443 TCP/SNI local inbound offload${PLAIN}" "${BOLD}удален 443 TCP/SNI локальная входящая разгрузка${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    if [[ ${#TCP_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有可删除的 TCP/SNI 入站分流。${PLAIN}" "${YELLOW}Currently has no TCP/SNI inbound offloads that can be deleted.${PLAIN}" "${YELLOW}в настоящее время не имеет входящих разгрузок TCP/SNI, которые можно удалить.${PLAIN}")"
        return 0
    fi

    local i num choice idx route_sni
    local -a new_snis=()
    local -a new_addrs=()
    local -a new_ports=()
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${TCP_ROUTE_SNIS[$i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$i]}:${TCP_ROUTE_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "$(localized_text "请输入要删除的序号: " "Please enter the serial number to be deleted:" "Пожалуйста, введите серийный номер, который необходимо удалить:")"
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消删除。${PLAIN}" "${BLUE}Has been canceled.${PLAIN}" "${BLUE}отменен.${PLAIN}")"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#TCP_ROUTE_SNIS[@]} )); then
        echo -e "$(localized_text "${RED}❌ 序号无效。${PLAIN}" "${RED}❌ The serial number is invalid.${PLAIN}" "${RED}❌ Серийный номер недействителен.${PLAIN}")"
        return 1
    fi

    idx=$((choice - 1))
    route_sni="${TCP_ROUTE_SNIS[$idx]}"
    confirm_risk_action "$(localized_text "从 443 分流中移除 TCP/SNI 入站 ${route_sni}" "Remove TCP/SNI from 443 routing inbound ${route_sni}" "Удалить входящее подключение TCP/SNI из маршрутизации 443 ${route_sni}.")" \
        "$(localized_text "该 SNI 的 Nginx stream 直通规则" "The Nginx stream pass-through rule for SNI" "Правило прохождения Nginx stream для SNI")" \
        "$(localized_text "使用 443 单入口备份恢复，或重新新增该 TCP/SNI 入站" "Use 443 shared entry backup and restore, or re-add the TCP/SNI inbound connection" "Используйте однократное резервное копирование и восстановление 443 или повторно добавьте входящий TCP/SNI.")" \
        "$(localized_text "确认没有客户端仍依赖该 SNI 连接。" "Confirm that no clients are still relying on the SNI connection." "Убедитесь, что ни один клиент по-прежнему не использует соединение SNI.")" || return 1

    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_snis+=("${TCP_ROUTE_SNIS[$i]}")
        new_addrs+=("${TCP_ROUTE_ADDRS[$i]}")
        new_ports+=("${TCP_ROUTE_PORTS[$i]}")
    done
    TCP_ROUTE_SNIS=("${new_snis[@]}")
    TCP_ROUTE_ADDRS=("${new_addrs[@]}")
    TCP_ROUTE_PORTS=("${new_ports[@]}")
    remove_sni_ip_whitelist_for_domain "$route_sni"
    save_and_offer_reapply_sni_stack
}
