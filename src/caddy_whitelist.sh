# shellcheck shell=bash
# Caddy/Web domain whitelist config block manipulation and menu flow.

strip_caddy_ip_whitelist_block() {
    local conf_file="$1"
    local tmp_file
    tmp_file=$(mktemp /tmp/caddy-ipwl.XXXXXX) || return 1
    awk '
        /# vps-optimize-ip-whitelist-start/ {skip=1; next}
        /# vps-optimize-ip-whitelist-end/ {skip=0; next}
        !skip {print}
    ' "$conf_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv "$tmp_file" "$conf_file"
}

insert_caddy_ip_whitelist_block() {
    local conf_file="$1"
    local ranges="$2"
    local tmp_file block
    strip_caddy_ip_whitelist_block "$conf_file" || return 1
    tmp_file=$(mktemp /tmp/caddy-ipwl.XXXXXX) || return 1
    block=$(caddy_ip_whitelist_block "$ranges")
    awk -v block="$block" '
        inserted == 0 && /^[[:space:]]*[^#[:space:]].*\{[[:space:]]*$/ {
            print
            printf "%s", block
            inserted=1
            next
        }
        {print}
        END { if (inserted == 0) exit 1 }
    ' "$conf_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv "$tmp_file" "$conf_file"
}

func_caddy_manage_ip_whitelist() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔐 Caddy 域名 IP 白名单${PLAIN}" "${BOLD}🔐 Caddy domain IP whitelist${PLAIN}" "${BOLD}🔐 Caddy доменное имя Белый список IP-адресов${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}适用于未启用 443 单入口、由 Caddy 直接对外服务的域名。${PLAIN}" "${YELLOW}Suitable for domains that do not enable the 443 shared entry and are directly served externally by Caddy.${PLAIN}" "${YELLOW}подходит для доменных имен, которые не поддерживают общий вход 443 и обслуживаются напрямую извне Caddy.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如果该域名已接入 443 单入口，请用主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]，不要在 Caddy 层限制。${PLAIN}" "${YELLOW}If the domain has been connected to 443 shared entry, please use the main menu [19 443 shared entry management center] -> [8 Manage Web domain/reverse proxy] -> [5 Manage domain IP whitelist], do not limit it at the Caddy layer.${PLAIN}" "${YELLOW}Если доменное имя подключено к 443 единому входу, используйте главное меню [19 443 центр управления общим входом] -> [8 Управление именем веб-домена/обратным прокси-сервером] -> [5 Управление белым списком IP-адресов доменного имени], не ограничивайте его на уровне Caddy.${PLAIN}")"
    echo -e "------------------------------------------------"

    if ! command -v caddy >/dev/null 2>&1 || [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e "$(localized_text "${RED}❌ 未检测到 Caddy 或 /etc/caddy/Caddyfile，请先配置 Caddy 反代。${PLAIN}" "${RED}❌ Caddy or /etc/caddy/Caddyfile is not detected, please configure Caddy reverse proxy first.${PLAIN}" "${RED}❌ Caddy или /etc/caddy/Caddyfile не обнаружен, сначала настройте обратный прокси-сервер Caddy.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi

    local domain conf_file first_site_line action backup_file
    read_trimmed domain "$(localized_text "请输入要管理的域名 (如 panel.example.com): " "Please enter the domain you want to manage (eg panel.example.com):" "Пожалуйста, введите доменное имя, которым вы хотите управлять (например, Panel.example.com):")"
    domain=$(normalize_domain_input "$domain")
    if ! is_valid_domain "$domain"; then
        echo -e "$(localized_text "${RED}❌ 域名格式无效。${PLAIN}" "${RED}❌ The domain format is invalid.${PLAIN}" "${RED}❌ Неверный формат доменного имени.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi

    conf_file="/etc/caddy/conf.d/${domain}.caddy"
    if [[ ! -f "$conf_file" ]]; then
        echo -e "$(localized_text "${RED}❌ 未找到 ${conf_file}。该入口只管理脚本创建的模块化 Caddy 域名配置。${PLAIN}" "${RED}❌ ${conf_file} not found. This entry only manages the modular Caddy domain configuration created by the script.${PLAIN}" "${RED}❌ ${conf_file} не найден. Эта запись управляет только модульной конфигурацией доменного имени Caddy, созданной сценарием.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi

    first_site_line=$(grep -m1 -E '^[[:space:]]*[^#[:space:]].*\{' "$conf_file" 2>/dev/null | sed 's/^[[:space:]]*//')
    if [[ "$first_site_line" != "$domain "* && "$first_site_line" != "$domain{"* && "$first_site_line" != "https://${domain}"* ]]; then
        echo -e "$(localized_text "${RED}❌ ${conf_file} 的首个站点块不是 ${domain}，为避免误改已取消。${PLAIN}" "${RED}❌ The first site block of ${conf_file} is not ${domain}, and has been canceled to avoid mistaken modification.${PLAIN}" "${RED}❌ Первый блок сайта ${conf_file} — это не ${domain}, и он был отменен во избежание ошибочной модификации.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi
    if [[ "$first_site_line" =~ ^https://[^[:space:]]+:[0-9]+[[:space:]]*\{ ]]; then
        echo -e "$(localized_text "${RED}❌ 这个配置看起来属于 443 单入口本地 Caddy TLS 站点。请改用主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]。${PLAIN}" "${RED}❌ This configuration appears to belong to the 443 shared entry local Caddy TLS site. Please use the main menu instead [19 443 shared entry Management Center] -> [8 Manage Web domain/Reverse Proxy] -> [5 Manage domain IP Whitelist].${PLAIN}" "${RED}❌ Похоже, эта конфигурация принадлежит локальному сайту Caddy TLS с общей точкой входа 443. Вместо этого используйте главное меню [19 443 Центр управления общим входом] -> [8 Управление именем веб-домена/обратным прокси-сервером] -> [5 Управление белым списком IP-адресов доменных имен].${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi

    echo -e "$(localized_text "当前配置文件：${conf_file}" "Current configuration file: ${conf_file}" "Текущий файл конфигурации: ${conf_file}.")"
    if grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
        echo -e "$(localized_text "${YELLOW}当前状态：已启用脚本管理的 IP 白名单。${PLAIN}" "${YELLOW}Current status: IP whitelist for script management is enabled.${PLAIN}" "${YELLOW}Текущее состояние: белый список IP-адресов для управления сценариями включен.${PLAIN}")"
    else
        echo -e "$(localized_text "${BLUE}当前状态：未启用脚本管理的 IP 白名单。${PLAIN}" "${BLUE}Current status: IP whitelist for script management is not enabled.${PLAIN}" "${BLUE}Текущий статус: Белый список IP-адресов для управления сценариями не включен.${PLAIN}")"
    fi
    echo -e "$(localized_text "1. 设置/覆盖白名单" "1. Set/override whitelist" "1. Установить/переопределить белый список")"
    echo -e "$(localized_text "2. 清除白名单" "2. Clear the whitelist" "2. Очистите белый список")"
    echo -e "$(localized_text "0. 取消" "0. Cancel" "0. Отмена")"
    read_trimmed action "$(localized_text "请选择操作: " "Please select an action:" "Пожалуйста, выберите действие:")"

    backup_file="${conf_file}.bak_$(date +%s)"
    case "$action" in
        1)
            local ip_whitelist_input ip_whitelist_ranges current_client_ip
            local -a ip_whitelist_array=()
            current_client_ip=$(detect_ssh_client_ip)
            [[ -n "$current_client_ip" ]] && echo -e "$(localized_text "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}" "${YELLOW}The current source IP of SSH may be: ${current_client_ip}. Please confirm that it has been added to the whitelist.${PLAIN}" "${YELLOW}Текущий исходный IP-адрес SSH может быть: ${current_client_ip}. Пожалуйста, подтвердите, что он был добавлен в белый список.${PLAIN}")"
            read_trimmed ip_whitelist_input "$(localized_text "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: " "Please enter the IP/CIDR that allows access to ${domain} (separate multiple by spaces or commas):" "Введите IP/CIDR, который разрешает доступ к ${domain} (разделяйте кратные пробелами или запятыми):")"
            if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
                echo -e "$(localized_text "${RED}❌ 白名单为空或格式错误，已取消操作。${PLAIN}" "${RED}❌ The whitelist is empty or has an incorrect format, and the operation has been cancelled.${PLAIN}" "${RED}❌ Белый список пуст или имеет неверный формат, и операция отменена.${PLAIN}")"
                read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                return
            fi
            append_vps_public_ips_to_whitelist ip_whitelist_array
            ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
            cp -p "$conf_file" "$backup_file" || { echo -e "$(localized_text "${RED}❌ 备份失败，已取消。${PLAIN}" "${RED}❌ Backup failed and has been cancelled.${PLAIN}" "${RED}❌ Резервное копирование не выполнено и было отменено.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"; return; }
            if insert_caddy_ip_whitelist_block "$conf_file" "$ip_whitelist_ranges" && caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                if systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1; then
                    echo -e "$(localized_text "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ IP whitelist enabled for ${domain}: ${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ Белый список IP-адресов включен для ${domain}: ${ip_whitelist_ranges}${PLAIN}")"
                    echo -e "$(localized_text "${CYAN}配置备份已保留：${backup_file}${PLAIN}" "${CYAN}Configuration backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия конфигурации сохранена: ${backup_file}.${PLAIN}")"
                else
                    echo -e "$(localized_text "${RED}❌ Caddy 重载失败，正在回滚...${PLAIN}" "${RED}❌ Caddy Reload failed, rolling back...${PLAIN}" "${RED}❌ Caddy Ошибка перезагрузки, откат...${PLAIN}")"
                    mv "$backup_file" "$conf_file"
                    systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
                fi
            else
                echo -e "$(localized_text "${RED}❌ 写入后 Caddy 校验失败，正在回滚...${PLAIN}" "${RED}❌ After writing Caddy verification failed, rolling back...${PLAIN}" "${RED}❌ После записи Caddy проверка не удалась, откат...${PLAIN}")"
                mv "$backup_file" "$conf_file"
            fi
            ;;
        2)
            if ! grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
                echo -e "$(localized_text "${BLUE}该域名没有脚本管理的白名单块，无需清除。${PLAIN}" "${BLUE}This domain does not have a script-managed whitelist block and does not need to be cleared.${PLAIN}" "${BLUE}Это доменное имя не имеет блока белого списка, управляемого сценарием, и его не нужно очищать.${PLAIN}")"
                read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                return
            fi
            cp -p "$conf_file" "$backup_file" || { echo -e "$(localized_text "${RED}❌ 备份失败，已取消。${PLAIN}" "${RED}❌ Backup failed and has been cancelled.${PLAIN}" "${RED}❌ Резервное копирование не выполнено и было отменено.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"; return; }
            if strip_caddy_ip_whitelist_block "$conf_file" && caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
                echo -e "$(localized_text "${GREEN}✅ 已清除 ${domain} 的 IP 白名单。${PLAIN}" "${GREEN}✅ The IP whitelist of ${domain} has been cleared.${PLAIN}" "${GREEN}✅ Белый список IP-адресов ${domain} очищен.${PLAIN}")"
                echo -e "$(localized_text "${CYAN}配置备份已保留：${backup_file}${PLAIN}" "${CYAN}Configuration backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия конфигурации сохранена: ${backup_file}.${PLAIN}")"
            else
                echo -e "$(localized_text "${RED}❌ 清除后 Caddy 校验失败，正在回滚...${PLAIN}" "${RED}❌ After clearing Caddy Verification failed, rolling back...${PLAIN}" "${RED}❌ После очистки Caddy проверка не удалась, откат...${PLAIN}")"
                mv "$backup_file" "$conf_file"
            fi
            ;;
        0|"")
            echo -e "$(localized_text "${BLUE}已取消。${PLAIN}" "${BLUE}Has been cancelled.${PLAIN}" "${BLUE}отменен.${PLAIN}")"
            ;;
        *)
            echo -e "$(localized_text "${RED}❌ 无效操作。${PLAIN}" "${RED}❌ Invalid operation.${PLAIN}" "${RED}❌ Недопустимая операция.${PLAIN}")"
            ;;
    esac

    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}
# ---------------------------------------------------------
# 优化重构：核弹级域名证书清理与解除端口占用 (模块化安全版)
# ---------------------------------------------------------
