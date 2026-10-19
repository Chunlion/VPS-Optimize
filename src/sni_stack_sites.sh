# shellcheck shell=bash
# Port 443 Reuse web-domain and custom TCP-route CRUD workflows.

list_sni_stack_sites() {
    load_sni_stack_env || return 1
    local web_engine web_label
    web_engine=$(current_web_proxy_engine)
    web_label=$(web_proxy_engine_label "$web_engine")
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}443端口复用：Web 域名与反向代理${PLAIN}" "${BOLD}Port 443 Reuse: Web domains and reverse proxies${PLAIN}" "${BOLD}Повторное использование порта 443: Web-домены и обратные прокси${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "Web 反代引擎：${web_label} (${web_engine}) -> $(web_proxy_backend)" "Web reverse proxy engine: ${web_label} (${web_engine}) -> $(web_proxy_backend)" "механизм веб-прокси: ${web_label} (${web_engine}) -> $(web_proxy_backend)")"
    echo -e "$(localized_text "面板域名：${PANEL_DOMAIN} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Panel domain: ${PANEL_DOMAIN} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Доменное имя панели: ${PANEL_DOMAIN} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}")"
    local panel_ranges
    panel_ranges=$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")
    [[ -n "$panel_ranges" ]] && echo -e "$(localized_text "${YELLOW}面板域名 IP 白名单：${panel_ranges}${PLAIN}" "${YELLOW}Panel domain IP whitelist: ${panel_ranges}${PLAIN}" "${YELLOW}Белый список IP-адресов доменного имени панели : ${panel_ranges}${PLAIN}")"
    echo -e "REALITY SNI：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]] && echo -e "$(localized_text "${CYAN}另有 ${#TCP_ROUTE_SNIS[@]} 个旧 TCP/SNI 入站。${PLAIN}" "${CYAN}Plus ${#TCP_ROUTE_SNIS[@]} legacy TCP/SNI inbound(s).${PLAIN}" "${CYAN}Кроме того, есть старых входящих TCP/SNI: ${#TCP_ROUTE_SNIS[@]}.${PLAIN}")"
        [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]] && echo -e "$(localized_text "${CYAN}另有 ${#XRAY_SNI_ROUTE_SNIS[@]} 个 Xray 入站，请在 [19] -> [4] 查看。${PLAIN}" "${CYAN}Plus ${#XRAY_SNI_ROUTE_SNIS[@]} Xray inbound(s); check them at [19] -> [4].${PLAIN}" "${CYAN}Кроме того, есть входящих Xray: ${#XRAY_SNI_ROUTE_SNIS[@]}; проверьте их в [19] -> [4].${PLAIN}")"
    echo -e "------------------------------------------------"
    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有额外的 Web 域名或反向代理。${PLAIN}" "${YELLOW}No additional Web domains or reverse proxies.${PLAIN}" "${YELLOW}Дополнительных Web-доменов и обратных прокси нет.${PLAIN}")"
        return 0
    fi

    local i num
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} https://${SITE_DOMAINS[$i]}/ -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
        local site_ranges
        site_ranges=$(sni_ip_whitelist_ranges_for_domain "${SITE_DOMAINS[$i]}")
        [[ -n "$site_ranges" ]] && echo -e "$(localized_text "   ${YELLOW}IP 白名单：${site_ranges}${PLAIN}" "${YELLOW}IP whitelist: ${site_ranges}${PLAIN}" "Белый список ${YELLOW}IP: ${site_ranges}${PLAIN}")"
    done
}

add_sni_stack_site() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}新增 Web 域名与反向代理${PLAIN}" "${BOLD}Add a Web domain or reverse proxy${PLAIN}" "${BOLD}Добавление Web-домена или обратного прокси${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    if [[ ! -f "$cf_env_file" ]]; then
        echo -e "$(localized_text "${RED}❌ 未找到 Cloudflare Token，请先进入维护菜单 [2] 写入 Token。${PLAIN}" "${RED}❌ Cloudflare Token was not found. Please enter the maintenance menu [2] to write the Token first.${PLAIN}" "${RED}❌ Cloudflare Токен не найден. Пожалуйста, войдите в меню обслуживания [2], чтобы сначала записать токен.${PLAIN}")"
        return 1
    fi
    source "$cf_env_file"
    if [[ -z "${CF_Token:-}" ]]; then
        echo -e "$(localized_text "${RED}❌ Cloudflare Token 为空，请先进入维护菜单 [2] 更新。${PLAIN}" "${RED}❌ Cloudflare Token is empty, please enter the maintenance menu [2] to update first.${PLAIN}" "${RED}❌ Cloudflare Токен пуст, войдите в меню обслуживания [2] для обновления.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "这个入口适合后续新增网站，例如 SublinkPro、Dockge、博客或订阅管理工具。" "Use this entry to add sites later, such as SublinkPro, Dockge, a blog, or subscription management tools." "Этот раздел предназначен для добавления сайтов: SublinkPro, Dockge, блога или инструментов управления подписками.")"
    local web_engine web_label
    web_engine=$(current_web_proxy_engine)
    web_label=$(web_proxy_engine_label "$web_engine")
    echo -e "$(localized_text "${YELLOW}新增域名会走：公网 ${NGINX_LISTEN_PORT} -> 443 入口分流 -> ${web_label} -> 本地后端。${PLAIN}" "${YELLOW}The new domain will go to: public ${NGINX_LISTEN_PORT} -> 443 entry routing -> ${web_label} -> local backend.${PLAIN}" "${YELLOW}Новое доменное имя будет передано в: публичную сеть ${NGINX_LISTEN_PORT} -> маршрутизация входа 443 -> ${web_label} -> локальный сервер.${PLAIN}")"
    echo -e ""

    local site_domain site_domain_input site_addr site_port advanced_mode existing idx confirm
    local enable_ip_whitelist whitelist_input whitelist_ranges current_client_ip
    local -a whitelist_array=()
    read_trimmed site_domain_input "$(localized_text "新 Web 域名（仅域名；示例值 site.example.com）: " "New Web domain (hostname only; example: site.example.com): " "Новый Web-домен (только имя; пример: site.example.com): ")"
    site_domain=$(normalize_domain_input "$site_domain_input")
    if [[ -z "$site_domain" || "$site_domain" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消新增 Web 域名与反向代理。${PLAIN}" "${BLUE}Cancelled adding the Web domain or reverse proxy.${PLAIN}" "${BLUE}Добавление Web-домена или обратного прокси отменено.${PLAIN}")"
        return 0
    fi

    if ! is_valid_domain "$site_domain"; then
        print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$site_domain_input" "$site_domain"
        return 1
    fi
    if [[ "$site_domain" == "$PANEL_DOMAIN" || "$site_domain" == "$REALITY_SNI" ]]; then
        echo -e "$(localized_text "${RED}❌ 新域名不能和面板域名或 REALITY SNI 相同。${PLAIN}" "${RED}❌ The new domain cannot be the same as the panel domain or REALITY SNI.${PLAIN}" "${RED}❌ Новое доменное имя не может совпадать с именем домена панели или REALITY SNI.${PLAIN}")"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        if [[ "$site_domain" == "$existing" ]]; then
            echo -e "$(localized_text "${RED}❌ 该域名已经在 443 分流列表中。${PLAIN}" "${RED}❌ This domain is already in the 443 routing list.${PLAIN}" "${RED}❌ Это доменное имя уже находится в списке маршрутизация 443.${PLAIN}")"
            return 1
        fi
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        if [[ "$site_domain" == "$existing" ]]; then
            echo -e "$(localized_text "${RED}❌ 该域名已经作为 TCP/SNI 入站使用。${PLAIN}" "${RED}❌ This domain has been used inbound as TCP/SNI.${PLAIN}" "${RED}❌ Это доменное имя использовалось в качестве TCP/SNI.${PLAIN}")"
            return 1
        fi
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        if [[ "$site_domain" == "$existing" ]]; then
            echo -e "$(localized_text "${RED}❌ 该域名已经作为 Xray 入站使用。${PLAIN}" "${RED}❌ This domain has been used inbound as Xray.${PLAIN}" "${RED}❌ Это доменное имя использовалось в качестве Xray.${PLAIN}")"
            return 1
        fi
    done

    read_trimmed advanced_mode "$(localized_text "后端是否使用自定义地址？(Y/n，默认 y): " "Does the backend use custom addresses? (Y/n, default y):" "Использует ли бэкенд собственные адреса? (Да/нет, по умолчанию y):")"
    if is_yes "$advanced_mode"; then
        site_addr=$(ask_with_default "$(localized_text "后端地址" "Backend address" "Внутренний адрес")" "127.0.0.1")
    else
        site_addr="127.0.0.1"
        echo -e "$(localized_text "${GREEN}后端地址使用 127.0.0.1。${PLAIN}" "${GREEN}Backend address uses 127.0.0.1.${PLAIN}" "${GREEN}Внутренний адрес использует 127.0.0.1.${PLAIN}")"
    fi
    site_addr=$(normalize_backend_addr_input "$site_addr")
    site_port=$(ask_with_default "$(localized_text "程序实际监听端口（显示值仅供参考）" "App listening port (displayed value is for reference)" "Порт приложения (показанное значение для справки)")" "$((3000 + ${#SITE_DOMAINS[@]}))")

    is_valid_backend_addr "$site_addr" || { echo -e "$(localized_text "${RED}❌ 后端地址无效：${site_addr}${PLAIN}" "${RED}❌ Invalid backend address: ${site_addr}${PLAIN}" "${RED}❌ Неверный внутренний адрес: ${site_addr}.${PLAIN}")"; return 1; }
    is_valid_port "$site_port" || { echo -e "$(localized_text "${RED}❌ 后端端口无效：${site_port}${PLAIN}" "${RED}❌ Invalid backend port: ${site_port}${PLAIN}" "${RED}❌ Неверный внутренний порт: ${site_port}.${PLAIN}")"; return 1; }
    warn_if_public_bind "$(localized_text "反向代理后端 ${site_domain}" "Reverse proxy backend ${site_domain}" "Бэкенд обратного прокси ${site_domain}")" "$site_addr" "$site_port" || return 1
    confirm_backend_target_or_continue "$(localized_text "反向代理后端 ${site_domain}" "Reverse proxy backend ${site_domain}" "Бэкенд обратного прокси ${site_domain}")" "$site_addr" "$site_port" || return 1

    if web_proxy_engine_supports_web_whitelist "${ENTRY_MODE:-$(get_entry_mode)}" "$web_engine"; then
        read_trimmed enable_ip_whitelist "$(localized_text "是否为 ${site_domain} 启用 IP 白名单？(y/N，默认 N): " "Enable an IP allowlist for ${site_domain}? (y/N, default N): " "Включить список разрешённых IP-адресов для ${site_domain}? (y/N, по умолчанию N): ")"
    else
        echo -e "$(localized_text "${YELLOW}xray-fallback 无法让本地 Web 反代引擎可靠获取真实客户端源 IP，本次禁止为新域名启用 Web 白名单。${PLAIN}" "${YELLOW}Xray-fallback cannot allow the local web reverse proxy engine to reliably obtain the real client source IP. This time, it is prohibited to enable the web whitelist for new domains.${PLAIN}" "${YELLOW}xray-резервный вариант не может позволить локальному механизму веб-прокси надежно получить реальный исходный IP-адрес клиента. На этот раз запрещено включать белый список веб-сайтов для новых доменных имен.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}如需 Web 白名单，请改用 Nginx Stream/TCP Peek 入口模式。${PLAIN}" "${YELLOW}If you need Web whitelist, please use Nginx Stream/TCP Peek entry mode instead.${PLAIN}" "${YELLOW}Если вам нужен белый список веб-страниц, используйте вместо этого режим входа Nginx Stream/TCP Peek.${PLAIN}")"
        enable_ip_whitelist="n"
    fi
    if is_yes "$enable_ip_whitelist"; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "$(localized_text "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}" "${YELLOW}The current source IP of SSH may be: ${current_client_ip}. Please confirm that it has been added to the whitelist.${PLAIN}" "${YELLOW}Текущий исходный IP-адрес SSH может быть: ${current_client_ip}. Пожалуйста, подтвердите, что он был добавлен в белый список.${PLAIN}")"
        read_trimmed whitelist_input "$(localized_text "请输入允许访问 ${site_domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: " "Please enter the IP/CIDR that allows access to ${site_domain} (separate multiple by spaces or commas):" "Введите IP/CIDR, который разрешает доступ к ${site_domain} (разделяйте кратные пробелами или запятыми):")"
        normalize_ip_whitelist_input "$whitelist_input" whitelist_array || return 1
        append_vps_public_ips_to_whitelist whitelist_array
        whitelist_ranges=$(join_array_by_space "${whitelist_array[@]}")
    fi

    echo -e ""
    echo -e "$(localized_text "${CYAN}即将添加：${site_domain} -> ${site_addr}:${site_port}${PLAIN}" "${CYAN}Will be added soon: ${site_domain} -> ${site_addr}:${site_port}${PLAIN}" "${CYAN}скоро будет добавлен: ${site_domain} -> ${site_addr}:${site_port}${PLAIN}")"
    [[ -n "${whitelist_ranges:-}" ]] && echo -e "$(localized_text "${YELLOW}IP 白名单：${whitelist_ranges}${PLAIN}" "${YELLOW}IP whitelist: ${whitelist_ranges}${PLAIN}" "${YELLOW}Белый список IP: ${whitelist_ranges}${PLAIN}")"
    confirm_risk_action "$(localized_text "新增 Web 域名与反向代理 ${site_domain}" "Add the Web domain or reverse proxy ${site_domain}" "Добавить Web-домен или обратный прокси ${site_domain}")" \
        "$(localized_text "证书、Web 反代引擎配置和 443 入口分流配置" "Certificate, Web reverse proxy engine configuration and 443 entry routing configuration" "Сертификат, конфигурация механизма веб-прокси и конфигурация перенаправления входа 443.")" \
        "$(localized_text "使用 443端口复用备份恢复，或从网站管理菜单删除该域名" "Use the Port 443 Reuse backup and restore, or delete the domain from the website management menu" "Используйте резервную копию повторного использования порта 443 для восстановления или удаления домена из меню управления веб-сайтом.")" \
        "$(localized_text "确认域名已解析到当前 VPS，后端端口可从本机访问。" "Confirm that the domain has been resolved to the current VPS and the backend port can be accessed from this machine." "Убедитесь, что доменное имя было преобразовано в текущий VPS и доступ к внутреннему порту возможен с этого компьютера.")" || return 1

    idx=${#SITE_DOMAINS[@]}
    SITE_DOMAINS[$idx]="$site_domain"
    SITE_BACKEND_ADDRS[$idx]="$site_addr"
    SITE_BACKEND_PORTS[$idx]="$site_port"
    [[ -n "${whitelist_ranges:-}" ]] && set_sni_ip_whitelist_for_domain "$site_domain" "$whitelist_ranges"

    issue_and_install_cert_for_domain "$site_domain" "$CF_Token" || return 1
    apply_sni_stack_runtime_config || return 1
    echo -e "$(localized_text "${GREEN}✅ 已添加网站入口：https://${site_domain}/${PLAIN}" "${GREEN}✅ Website entry has been added: https://${site_domain}/${PLAIN}" "${GREEN}✅ Добавлен вход на сайт: https://${site_domain}/${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}提醒：当前 VPS 必须能访问 ${site_addr}:${site_port}，浏览器只访问 https://${site_domain}/。${PLAIN}" "${YELLOW}Reminder: The current VPS must be able to access ${site_addr}:${site_port}, and the browser can only access https://${site_domain}/。${PLAIN}" "${YELLOW}Напоминание : текущий VPS должен иметь доступ к ${site_addr}:${site_port}, а браузер может получить доступ только к https://${site_domain}/。.${PLAIN}")"
    echo -e "$(localized_text "${CYAN}当前 Web 反代后端：${web_label} -> ${site_addr}:${site_port}${PLAIN}" "${CYAN}Current Web reverse proxy backend: ${web_label} -> ${site_addr}:${site_port}${PLAIN}" "${CYAN}Текущий сервер веб-прокси: ${web_label} -> ${site_addr}:${site_port}${PLAIN}")"
}

edit_sni_stack_site_backend() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}修改反向代理后端${PLAIN}" "${BOLD}Edit a reverse-proxy backend${PLAIN}" "${BOLD}Изменение бэкенда обратного прокси${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有可修改的网站/反代域名。${PLAIN}" "${YELLOW}Currently there is no website/reverse domain that can be modified.${PLAIN}" "${YELLOW}В настоящее время не существует веб-сайта/обратного доменного имени, которое можно было бы изменить.${PLAIN}")"
        return 0
    fi

    local i num choice idx domain new_addr new_port confirm
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${SITE_DOMAINS[$i]} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "$(localized_text "请输入要修改的序号: " "Please enter the serial number to be modified:" "Пожалуйста, введите серийный номер, который необходимо изменить:")"
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消修改。${PLAIN}" "${BLUE}Edit canceled.${PLAIN}" "${BLUE}Изменение отменено.${PLAIN}")"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#SITE_DOMAINS[@]} )); then
        echo -e "$(localized_text "${RED}❌ 序号无效。${PLAIN}" "${RED}❌ The serial number is invalid.${PLAIN}" "${RED}❌ Серийный номер недействителен.${PLAIN}")"
        return 1
    fi

    idx=$((choice - 1))
    domain="${SITE_DOMAINS[$idx]}"
    new_addr=$(ask_with_default "$(localized_text "后端地址" "Backend address" "Внутренний адрес")" "${SITE_BACKEND_ADDRS[$idx]}")
    new_addr=$(normalize_backend_addr_input "$new_addr")
    new_port=$(ask_with_default "$(localized_text "程序实际监听端口（显示值仅供参考）" "App listening port (displayed value is for reference)" "Порт приложения (показанное значение для справки)")" "${SITE_BACKEND_PORTS[$idx]}")

    is_valid_backend_addr "$new_addr" || { echo -e "$(localized_text "${RED}❌ 后端地址无效：${new_addr}${PLAIN}" "${RED}❌ Invalid backend address: ${new_addr}${PLAIN}" "${RED}❌ Неверный внутренний адрес: ${new_addr}.${PLAIN}")"; return 1; }
    is_valid_port "$new_port" || { echo -e "$(localized_text "${RED}❌ 后端端口无效：${new_port}${PLAIN}" "${RED}❌ Invalid backend port: ${new_port}${PLAIN}" "${RED}❌ Неверный внутренний порт: ${new_port}.${PLAIN}")"; return 1; }
    warn_if_public_bind "$(localized_text "反向代理后端 ${domain}" "Reverse proxy backend ${domain}" "Бэкенд обратного прокси ${domain}")" "$new_addr" "$new_port" || return 1
    confirm_backend_target_or_continue "$(localized_text "反向代理后端 ${domain}" "Reverse proxy backend ${domain}" "Бэкенд обратного прокси ${domain}")" "$new_addr" "$new_port" || return 1

    echo -e ""
    echo -e "$(localized_text "${CYAN}即将修改：${domain} -> ${new_addr}:${new_port}${PLAIN}" "${CYAN}The following will be changed: ${domain} -> ${new_addr}:${new_port}${PLAIN}" "${CYAN}скоро будет изменен: ${domain} -> ${new_addr}:${new_port}${PLAIN}")"
    confirm_risk_action "$(localized_text "修改反向代理后端" "Edit the reverse proxy backend" "Изменить бэкенд обратного прокси")" \
        "$(localized_text "Web 反代引擎后端和 443 入口分流配置" "Web reverse proxy engine backend and 443 entry routing configuration" "бэкенд механизма веб-прокси и конфигурация перенаправления входа 443")" \
        "$(localized_text "使用 443端口复用备份恢复修改前配置" "Use Port 443 Reuse backup to restore the configuration before modification" "Используйте резервную копию повторного использования порта 443 для восстановления конфигурации до изменения.")" \
        "$(localized_text "确认当前 VPS 能访问新的后端地址和端口。" "Confirm that the current VPS can access the new backend address and port." "Убедитесь, что текущий VPS может получить доступ к новому внутреннему адресу и порту.")" || return 1

    SITE_BACKEND_ADDRS[$idx]="$new_addr"
    SITE_BACKEND_PORTS[$idx]="$new_port"
    apply_sni_stack_runtime_config || return 1
    echo -e "$(localized_text "${GREEN}✅ 已更新网站后端：https://${domain}/ -> ${new_addr}:${new_port}${PLAIN}" "${GREEN}✅ Updated website backend: https://${domain}/ -> ${new_addr}:${new_port}${PLAIN}" "${GREEN}✅ Обновлена бэкенд сайта: https://${domain}/ -> ${new_addr}:${new_port}${PLAIN}")"
    echo -e "$(localized_text "${CYAN}当前 Web 反代后端：$(web_proxy_engine_label) -> ${new_addr}:${new_port}${PLAIN}" "${CYAN}Current Web reverse proxy backend: $(web_proxy_engine_label) -> ${new_addr}:${new_port}${PLAIN}" "${CYAN}Текущий сервер веб-прокси: $(web_proxy_engine_label) -> ${new_addr}:${new_port}${PLAIN}")"
}

remove_sni_stack_site() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}删除 443 网站/反代域名${PLAIN}" "${BOLD}Deleted 443 websites/reverse domain${PLAIN}" "${BOLD}удалил 443 веб-сайта/обратное доменное имя${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有可删除的网站/反代域名。${PLAIN}" "${YELLOW}Currently there is no website/reverse domain that can be deleted.${PLAIN}" "${YELLOW}В настоящее время не существует веб-сайта/обратного доменного имени, которое можно было бы удалить.${PLAIN}")"
        return 0
    fi

    local i num choice idx domain confirm delete_cert new_domains new_addrs new_ports
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${SITE_DOMAINS[$i]} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "$(localized_text "请输入要删除的序号: " "Please enter the serial number to be deleted:" "Пожалуйста, введите серийный номер, который необходимо удалить:")"
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消删除。${PLAIN}" "${BLUE}Removal canceled.${PLAIN}" "${BLUE}Удаление отменено.${PLAIN}")"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#SITE_DOMAINS[@]} )); then
        echo -e "$(localized_text "${RED}❌ 序号无效。${PLAIN}" "${RED}❌ The serial number is invalid.${PLAIN}" "${RED}❌ Серийный номер недействителен.${PLAIN}")"
        return 1
    fi

    idx=$((choice - 1))
    domain="${SITE_DOMAINS[$idx]}"
    confirm_risk_action "$(localized_text "从 443 分流中移除 ${domain}" "Remove ${domain} from 443 routing" "Снимите ${domain} с маршрутизации 443.")" \
        "$(localized_text "该域名的 Web 反代引擎配置和 443 入口分流规则" "Web reverse proxy engine configuration and 443 entry routing rules for this domain" "Конфигурация механизма веб-прокси и правила перенаправления входа 443 для этого доменного имени.")" \
        "$(localized_text "使用 443端口复用备份恢复，或重新新增该网站/反代域名" "Use Port 443 Reuse backup and restore, or re-add the website/reverse proxy domain" "Используйте резервное копирование и восстановление повторного использования порта 443 или повторно добавьте доменное имя веб-сайта/обратного прокси-сервера.")" \
        "$(localized_text "确认该域名不再承载线上面板、订阅或网站。" "Confirm that the domain no longer hosts the online panel, subscription, or website." "Убедитесь, что в домене больше нет онлайн-панели, подписки или веб-сайта.")" || return 1

    new_domains=()
    new_addrs=()
    new_ports=()
    for i in "${!SITE_DOMAINS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_domains+=("${SITE_DOMAINS[$i]}")
        new_addrs+=("${SITE_BACKEND_ADDRS[$i]}")
        new_ports+=("${SITE_BACKEND_PORTS[$i]}")
    done
    SITE_DOMAINS=("${new_domains[@]}")
    SITE_BACKEND_ADDRS=("${new_addrs[@]}")
    SITE_BACKEND_PORTS=("${new_ports[@]}")
    remove_sni_ip_whitelist_for_domain "$domain"
    quarantine_path "/etc/caddy/conf.d/${domain}.caddy" "/etc/vps-optimize/quarantine/caddy-sni" >/dev/null 2>&1 || true

    apply_sni_stack_runtime_config || return 1

    read_trimmed delete_cert "$(localized_text "是否同时隔离 ${domain} 的 Caddy 证书文件？(y/N，默认 N): " "Also quarantine the Caddy certificate files for ${domain}? (y/N, default N): " "Также поместить файлы сертификата Caddy для ${domain} в карантин? (y/N, по умолчанию N): ")"
    if is_yes "$delete_cert"; then
        quarantine_path "/etc/caddy/certs/${domain}.crt" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        quarantine_path "/etc/caddy/certs/${domain}.key" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        quarantine_path "/root/cert/${domain}.crt" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        quarantine_path "/root/cert/${domain}.key" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        generate_caddy_cf_manifest
        echo -e "$(localized_text "${GREEN}✅ 已移除 ${domain} 的配置，并隔离本地证书文件。${PLAIN}" "${GREEN}✅ The configuration of ${domain} has been removed and the local certificate file has been isolated.${PLAIN}" "${GREEN}. Конфигурация ${domain} удалена, а локальный файл сертификата изолирован.${PLAIN}")"
    else
        echo -e "$(localized_text "${GREEN}✅ 已删除 ${domain} 的分流配置，证书文件已保留。${PLAIN}" "${GREEN}✅ The offload configuration of ${domain} has been deleted and the certificate file has been retained.${PLAIN}" "${GREEN}. Конфигурация разгрузки ${domain} была удалена, а файл сертификата сохранен.${PLAIN}")"
    fi
}

switch_sni_stack_web_proxy_engine() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}切换 443 Web 反代引擎${PLAIN}" "${BOLD}Switch the Port 443 Web reverse proxy${PLAIN}" "${BOLD}Смена Web-прокси для порта 443${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local current_engine current_label choice new_engine new_label entry_mode
    current_engine=$(current_web_proxy_engine)
    current_label=$(web_proxy_engine_label "$current_engine")
    entry_mode="${ENTRY_MODE:-$(get_entry_mode)}"

    echo -e "$(localized_text "当前入口模式：${entry_mode}" "Current entry mode: ${entry_mode}" "Текущий режим ввода: ${entry_mode}.")"
    echo -e "$(localized_text "当前 Web 反代引擎：${current_label} (${current_engine})" "Current web reverse proxy engine: ${current_label} (${current_engine})" "Текущий движок веб-прокси: ${current_label} (${current_engine})")"
    echo -e "$(localized_text "本地 TLS 后端：$(web_proxy_backend)" "Local TLS Backend: $(web_proxy_backend)" "Локальный сервер TLS: $(web_proxy_backend)")"
    echo -e "$(localized_text "读取来源：/etc/vps-optimize/sni-stack.env（脚本保存的 443 共享配置）" "Read source: /etc/vps-optimize/sni-stack.env（脚本保存的 Port 443 Reuse configuration)" "Источник чтения: общая конфигурация /etc/vps-optimize/sni-stack.env（脚本保存的 443)")"
    echo -e "$(localized_text "${YELLOW}切换时会按当前域名、证书、后端和白名单重新渲染所选引擎，并隔离另一套 443 本地 Web 反代配置。${PLAIN}" "${YELLOW}When switching, the selected engine will be re-rendered according to the current domain, certificate, backend and whitelist, and another set of 443 local web reverse proxy configuration will be isolated.${PLAIN}" "${YELLOW}При переключении выбранный движок будет перерисован в соответствии с текущим именем домена, сертификатом, бэкенд и белым списком, а другой набор из 443 локальных конфигураций веб-прокси будет изолирован.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如果你手工改过 Caddy/Nginx 文件但没有通过本菜单保存，请先在 [6]/[8] 同步脚本保存值后再切换。${PLAIN}" "${YELLOW}If you manually modified the Caddy/Nginx file but did not save it through this menu, please save the value in the [6]/[8] synchronization script before switching.${PLAIN}" "${YELLOW}Если вы вручную изменили файл Caddy/Nginx, но не сохранили его через это меню, сохраните значение в сценарии синхронизации [6]/[8] перед переключением.${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${GREEN}  1. Caddy 本地 HTTPS 反代${PLAIN}" "${GREEN}1. Caddy local HTTPS reverse proxy${PLAIN}" "${GREEN}1. Caddy локальный HTTPS обратный прокси${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  2. Nginx 本地 HTTPS 反代${PLAIN}" "${GREEN}2. Nginx local HTTPS reverse proxy${PLAIN}" "${GREEN}2. Nginx локальный HTTPS обратный прокси${PLAIN}")"
    echo -e "$(localized_text "${RED}  0. 取消${PLAIN}" "${RED}0. Cancel${PLAIN}" "${RED}0. Отмена${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    read_trimmed choice "$(localized_text "选择 Web 反代引擎（直接回车保持当前）: " "Select Web reverse proxy (press Enter to keep current): " "Выберите Web-прокси (Enter — оставить текущий): ")"
    case "$choice" in
        ""|0|q|Q)
            echo -e "$(localized_text "${BLUE}已取消切换 Web 反代引擎。${PLAIN}" "${BLUE}Canceled the switching of the web reverse proxy engine.${PLAIN}" "${BLUE}отменил включение механизма обратный прокси сети.${PLAIN}")"
            return 0
            ;;
        1) new_engine="caddy" ;;
        2) new_engine="nginx" ;;
        *)
            echo -e "$(localized_text "${RED}❌ 无效的 Web 反代引擎选择。${PLAIN}" "${RED}❌ Invalid web reverse proxy engine selection.${PLAIN}" "${RED}❌ Неверный выбор механизма веб-прокси.${PLAIN}")"
            return 1
            ;;
    esac

    new_label=$(web_proxy_engine_label "$new_engine")
    if [[ "$new_engine" == "$current_engine" ]]; then
        echo -e "$(localized_text "${BLUE}Web 反代引擎未变化，仍为 ${current_label}。${PLAIN}" "${BLUE}The Web reverse proxy engine has not changed and is still ${current_label}.${PLAIN}" "${BLUE}Механизм обратный прокси Web не изменился и остается ${current_label}.${PLAIN}")"
        return 0
    fi

    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -gt 0 ]] && ! web_proxy_engine_supports_web_whitelist "$entry_mode" "$new_engine"; then
        echo -e "$(localized_text "${RED}❌ 不能切换到 ${new_label}：当前为 xray-fallback 且已有 Web 白名单，本地 Web 反代引擎无法可靠获取真实客户端源 IP。${PLAIN}" "${RED}❌ cannot switch to ${new_label}: It is currently xray-fallback and has a web whitelist. The local web reverse proxy engine cannot reliably obtain the real client source IP.${PLAIN}" "${RED}❌ не может переключиться на ${new_label}: в настоящее время это резервный вариант xray и имеется белый список веб-сайтов. Механизм обратный прокси локальной сети не может надежно получить реальный исходный IP-адрес клиента.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}请先清除 Web 白名单，或改用 Nginx Stream/TCP Peek 入口模式后再切换。${PLAIN}" "${YELLOW}Please clear the Web whitelist first, or switch to Nginx Stream/TCP Peek entry mode before switching.${PLAIN}" "${YELLOW}Сначала очистите белый список Интернета или переключитесь в режим входа Nginx Stream/TCP Peek перед переключением.${PLAIN}")"
        return 1
    fi
    if ! web_proxy_engine_supports_web_whitelist "$entry_mode" "$new_engine"; then
        echo -e "$(localized_text "${YELLOW}⚠️ 当前入口模式为 xray-fallback，切换 Web 反代引擎后仍禁止新增 Web 白名单。${PLAIN}" "${YELLOW}⚠️ The current entry mode is xray-fallback. After switching the Web reverse proxy engine, new Web whitelists are still prohibited.${PLAIN}" "${YELLOW}⚠️ Текущий режим входа — xray-резервный. После переключения механизма обратный прокси Интернета новые белые списки Интернета по-прежнему запрещены.${PLAIN}")"
    fi

    confirm_risk_action "$(localized_text "切换 443 Web 反代引擎为 ${new_label}" "Switch the 443 Web reverse proxy engine to ${new_label}" "Переключите механизм обратный прокси 443 Web на ${new_label}.")" \
        "$(localized_text "重新生成 ${new_label} 配置，并隔离旧的 443 本地 Web 反代配置；公网 443 入口模式保持 ${entry_mode}" "Regenerate the ${new_label} configuration and isolate the old 443 local Web reverse proxy configuration; the public port 443 entry mode remains ${entry_mode}" "Восстановите конфигурацию ${new_label} и изолируйте старую локальную конфигурацию обратный прокси веб-страницы 443; режим входа в публичную сеть 443 остается ${entry_mode}")" \
        "$(localized_text "使用 443端口复用备份恢复，或切回 ${current_label} 后重新应用" "Use Port 443 Reuse backup and restore, or switch back to ${current_label} and reapply" "Используйте резервное копирование и восстановление повторного использования порта 443 или вернитесь к ${current_label} и повторите заявку.")" \
        "$(localized_text "确认本机 ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} 未被其他服务占用，且证书文件仍在 /etc/caddy/certs/。" "Confirm that the local machine ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} is not occupied by other services, and the certificate file is still in /etc/caddy/certs/." "Убедитесь, что локальный компьютер ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} не занят другими службами и файл сертификата все еще находится в /etc/caddy/certs/.")" || return 1

    WEB_PROXY_ENGINE="$new_engine"
    save_and_offer_reapply_sni_stack
}
