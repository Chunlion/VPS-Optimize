# shellcheck shell=bash
# Port 443 Reuse profile editing and reapply helpers.

save_and_offer_reapply_sni_stack() {
    local env_file env_backup
    env_file="/etc/vps-optimize/sni-stack.env"
    env_backup=""
    if [[ -f "$env_file" ]]; then
        env_backup="${env_file}.pre_reapply_$(date +%Y%m%d_%H%M%S)"
        cp -p "$env_file" "$env_backup" 2>/dev/null || env_backup=""
    fi
    save_sni_stack_env
    echo -e "$(localized_text "${GREEN}✅ 已保存新的 443端口复用运行参数。${PLAIN}" "${GREEN}✅ New Port 443 Reuse operating parameters have been saved.${PLAIN}" "${GREEN}. Сохранены новые 443 отдельных рабочих параметра.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}提示：保存后需要重新应用，Nginx/Caddy 才会使用新的域名、端口或路径。${PLAIN}" "${YELLOW}Tips: You need to reapply after saving, so that Nginx/Caddy will use the new domain, port or path.${PLAIN}" "${YELLOW}Советы: вам необходимо повторно подать заявку после сохранения, чтобы Nginx/Caddy использовал новое имя домена, порт или путь.${PLAIN}")"
    if confirm_danger \
        "$(localized_text "重新应用 443 配置" "Reapply the port 443 configuration" "Повторно применить конфигурацию порта 443")" \
        "$(localized_text "重新生成入口配置并重启 Nginx/Caddy" "regenerate the entry configuration and restart Nginx/Caddy" "заново создать конфигурацию точки входа и перезапустить Nginx/Caddy")" \
        "$(localized_text "失败时自动恢复本次修改前的参数文件" "restore the parameter file saved before this change if reapplication fails" "при ошибке восстановить файл параметров, сохранённый до этого изменения")"; then
        if ! reapply_sni_stack_from_env --yes; then
            if [[ -n "$env_backup" && -f "$env_backup" ]]; then
                cp -p "$env_backup" "$env_file" 2>/dev/null || true
                echo -e "$(localized_text "${YELLOW}⚠️ 已恢复重新应用前的参数文件：${env_backup}${PLAIN}" "${YELLOW}⚠️ The parameter file before re-application has been restored: ${env_backup}${PLAIN}" "${YELLOW}⚠️ Файл параметров до повторного применения восстановлен: ${env_backup}${PLAIN}")"
            fi
            return 1
        fi
    else
        echo -e "$(localized_text "${YELLOW}稍后可执行 [19] -> [6] 重新应用上次配置。${PLAIN}" "${YELLOW}Can be executed later [19] -> [6] to reapply the last configuration.${PLAIN}" "${YELLOW}можно выполнить позже [19] -> [6] для повторного применения последней конфигурации.${PLAIN}")"
        [[ -n "$env_backup" ]] && echo -e "$(localized_text "${CYAN}参数修改前备份已保留：${env_backup}${PLAIN}" "${CYAN}The backup before parameter modification has been retained: ${env_backup}${PLAIN}" "${CYAN}Резервная копия до изменения параметра была сохранена: ${env_backup}.${PLAIN}")"
    fi
}

restart_xui_panel_services_after_setting_update() {
    local service_name restarted=0
    for service_name in x-ui 3x-ui x-panel; do
        if systemctl list-unit-files "${service_name}.service" --no-legend 2>/dev/null | grep -q . || systemctl status "$service_name" >/dev/null 2>&1; then
            if systemctl restart "$service_name" >/dev/null 2>&1; then
                restarted=1
            else
                echo -e "$(localized_text "${YELLOW}⚠️ ${service_name} 重启失败，请稍后手动重启面板服务。${PLAIN}" "${YELLOW}⚠️ ${service_name} Restart failed, please manually restart the panel service later.${PLAIN}" "${YELLOW}⚠️ ${service_name} Не удалось перезапустить, перезапустите службу панели вручную позже.${PLAIN}")"
            fi
        fi
    done
    [[ "$restarted" -eq 1 ]] && echo -e "$(localized_text "${GREEN}✅ 已重启 3x-ui/x-ui 面板服务，使域名设置生效。${PLAIN}" "${GREEN}✅ The 3x-ui/x-ui panel service has been restarted to make the domain settings take effect.${PLAIN}" "${GREEN}✅ Служба панели 3x-ui/x-ui перезапущена, чтобы настройки доменного имени вступили в силу.${PLAIN}")"
}

update_xui_panel_domain_settings_for_single_443() {
    local old_domain="$1"
    local new_domain="$2"
    local db_path table_name backup_dir backup_file sql
    local checked=0 updated=0 failed=0 timestamp

    if xui_uses_postgresql; then
        echo -e "$(localized_text "${YELLOW}⚠️ 检测到 3x-ui 使用 PostgreSQL，跳过数据库自动同步。请在 3x-ui 中保持订阅监听 IP 为 127.0.0.1、监听域名留空，并将反向代理 URI 设置为 https://${new_domain}${SUB_URI_PATH}；节点 Host 使用实际节点域名和公网 443。${PLAIN}" "${YELLOW}⚠️ 3x-ui uses PostgreSQL, so database synchronization was skipped. In 3x-ui, keep the subscription listen IP at 127.0.0.1, leave the listen domain empty, and set Reverse Proxy URI to https://${new_domain}${SUB_URI_PATH}; use the actual node domain and public port 443 for the node Host.${PLAIN}" "${YELLOW}⚠️ 3x-ui использует PostgreSQL, поэтому синхронизация базы пропущена. В 3x-ui оставьте IP прослушивания подписки 127.0.0.1, домен прослушивания — пустым, задайте URI обратного прокси https://${new_domain}${SUB_URI_PATH}; в Host узла укажите фактический домен узла и публичный порт 443.${PLAIN}")"
        return 0
    fi

    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "$(localized_text "${CYAN}▶ 正在安装 sqlite3，用于同步 3x-ui 面板域名设置...${PLAIN}" "${CYAN}▶ Installing sqlite3 for synchronization of 3x-ui panel domain settings...${PLAIN}" "${CYAN}▶ Установка sqlite3 для синхронизации настроек доменного имени панели 3x-ui...${PLAIN}")"
        install_pkg sqlite3 sqlite >/dev/null 2>&1 || true
    fi
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 sqlite3，跳过自动同步 3x-ui 面板域名设置。${PLAIN}" "${YELLOW}⚠️ sqlite3 not detected, skipping automatic synchronization 3x-ui panel domain settings.${PLAIN}" "${YELLOW}⚠️ sqlite3 не обнаружен, автоматическая синхронизация пропускается. Настройки доменного имени панели 3x-ui.${PLAIN}")"
        return 0
    fi

    timestamp=$(date +%Y%m%d_%H%M%S)
    while IFS= read -r db_path; do
        [[ -f "$db_path" ]] || continue
        table_name=$(sqlite3 "$db_path" "select name from sqlite_master where type='table' and name in ('settings','setting') order by case name when 'settings' then 0 else 1 end limit 1;" 2>/dev/null || true)
        [[ "$table_name" == "settings" || "$table_name" == "setting" ]] || continue
        checked=1

        backup_dir="/root/x-ui-backups"
        mkdir -p "$backup_dir"
        backup_file="${backup_dir}/x-ui.db.panel_domain_${timestamp}.bak"
        if ! sqlite3 "$db_path" ".backup '${backup_file}'" >/dev/null 2>&1; then
            echo -e "$(localized_text "${YELLOW}⚠️ 备份 3x-ui 数据库失败，跳过自动同步：${db_path}${PLAIN}" "${YELLOW}⚠️ Backup 3x-ui database failed, automatic synchronization skipped: ${db_path}${PLAIN}" "${YELLOW}⚠️ Ошибка резервного копирования базы данных 3x-ui, автоматическая синхронизация пропущена: ${db_path}${PLAIN}")"
            failed=1
            continue
        fi

        sql="
update ${table_name} set value='' where lower(key)='webdomain';
update ${table_name} set value='' where lower(key)='subdomain';
update ${table_name} set value='https://${new_domain}${SUB_URI_PATH}' where lower(key)='suburi';
update ${table_name} set value='https://${new_domain}${CLASH_URI_PATH}' where lower(key)='subclashuri';
update ${table_name} set value=replace(replace(value,'https://${old_domain}','https://${new_domain}'),'http://${old_domain}','https://${new_domain}') where lower(key)='subjsonuri' and value like '%${old_domain}%';
"
        if sqlite3 "$db_path" "$sql" >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ 已同步 3x-ui 面板/订阅域名设置：${db_path}${PLAIN}" "${GREEN}✅ Synchronized 3x-ui panel/subscription domain settings: ${db_path}${PLAIN}" "${GREEN}✅ Синхронизированные настройки панели 3x-ui/доменного имени подписки: ${db_path}${PLAIN}")"
            echo -e "$(localized_text "${CYAN}数据库备份：${backup_file}${PLAIN}" "${CYAN}Database backup: ${backup_file}${PLAIN}" "${CYAN}Резервное копирование базы данных : ${backup_file}${PLAIN}")"
            updated=1
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 同步 3x-ui 面板域名设置失败：${db_path}${PLAIN}" "${YELLOW}⚠️ Synchronization 3x-ui Panel domain setting failed: ${db_path}${PLAIN}" "${YELLOW}⚠️ Синхронизация 3x-ui Не удалось настроить доменное имя панели: ${db_path}${PLAIN}")"
            failed=1
        fi
    done < <(find_xui_database_candidates)

    [[ "$updated" -eq 1 ]] && restart_xui_panel_services_after_setting_update
    if [[ "$failed" -eq 1 ]]; then
        echo -e "$(localized_text "${RED}❌ 3x-ui 面板域名设置未完整同步，已停止修改 443 面板域名。${PLAIN}" "${RED}❌ 3x-ui The panel domain settings are not completely synchronized, and the modification of the 443 panel domain has been stopped.${PLAIN}" "${RED}❌ 3x-ui Настройки доменного имени панели не полностью синхронизированы, и изменение доменного имени панели 443 остановлено.${PLAIN}")"
        return 1
    fi
    if [[ "$checked" -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未找到 3x-ui 数据库，跳过 3x-ui 面板内部域名同步。${PLAIN}" "${YELLOW}⚠️ 3x-ui database not found, skipping 3x-ui panel internal domain synchronization.${PLAIN}" "${YELLOW}⚠️ База данных 3x-ui не найдена, пропуская внутреннюю синхронизацию доменного имени панели 3x-ui.${PLAIN}")"
    fi
    return 0
}

edit_sni_stack_panel_subscription_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}修改 3x-ui 面板 / 订阅端口与路径${PLAIN}" "${BOLD}Modified 3x-ui panel / subscription port and path${PLAIN}" "${BOLD}модифицированная панель 3x-ui/порт и путь подписки${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "$(localized_text "${YELLOW}适用于：你在 3x-ui 里修改了面板端口、订阅端口、普通订阅路径或 Clash/Mihomo 路径。${PLAIN}" "${YELLOW}Applies to: You modified the panel port, subscription port, normal subscription path or Clash/Mihomo path in 3x-ui.${PLAIN}" "${YELLOW}применяется к: Вы изменили порт панели, порт подписки, обычный путь подписки или путь Clash/Mihomo в 3x-ui.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}注意：3x-ui 3.x 新安装选第 4 项 Skip SSL，再选 y 仅绑定 127.0.0.1；2.x 或旧配置仍需清空面板和订阅证书路径。${PLAIN}" "${YELLOW}Note: for a new 3x-ui 3.x installation, choose option 4, Skip SSL, then y to bind only to 127.0.0.1. For 2.x or existing installations, clear the panel and subscription certificate paths.${PLAIN}" "${YELLOW}Примечание: при новой установке 3x-ui 3.x выберите пункт 4 Skip SSL, затем y для привязки только к 127.0.0.1. В 2.x и существующих установках очистите пути сертификатов панели и подписки.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}修改前请先在 3x-ui 面板里保存对应设置，再来这里同步脚本。${PLAIN}" "${YELLOW}Before modifying , please save the corresponding settings in the 3x-ui panel, and then synchronize the script here.${PLAIN}" "${YELLOW}Перед изменением сохраните соответствующие настройки на панели 3x-ui, а затем синхронизируйте скрипт здесь.${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "当前面板后端：${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Current panel backend: ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Текущая панель управления: ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}.")"
    echo -e "$(localized_text "当前面板公网路径：${PANEL_WEB_PATH}" "Current panel public path: ${PANEL_WEB_PATH}" "Путь текущей панели в публичной сети: ${PANEL_WEB_PATH}.")"
    echo -e "$(localized_text "当前订阅后端：${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Current subscription backend: ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "бэкенд текущей подписки: ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}.")"
    echo -e "$(localized_text "当前普通订阅路径：${SUB_URI_PATH}" "Current common subscription path: ${SUB_URI_PATH}" "Текущий общий путь подписки: ${SUB_URI_PATH}.")"
    echo -e "$(localized_text "当前 Clash/Mihomo 路径：${CLASH_URI_PATH}" "Current Clash/Mihomo path: ${CLASH_URI_PATH}" "Текущий путь Clash/Mihomo: ${CLASH_URI_PATH}")"
    echo -e "------------------------------------------------"

    PANEL_LISTEN_ADDR=$(ask_with_default "$(localized_text "3x-ui 面板监听地址" "3x-ui panel listening address" "Адрес прослушивания панели 3x-ui")" "$PANEL_LISTEN_ADDR")
    PANEL_LISTEN_PORT=$(ask_with_default "$(localized_text "3x-ui 面板端口" "3x-ui panel port" "Порт панели 3x-ui")" "$PANEL_LISTEN_PORT")
    PANEL_WEB_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "3x-ui 面板公网路径 / webBasePath" "3x-ui public panel path / webBasePath" "Публичный путь панели 3x-ui / webBasePath")" "$PANEL_WEB_PATH")")
    SUB_LISTEN_ADDR=$(ask_with_default "$(localized_text "3x-ui 订阅服务监听地址" "3x-ui Subscription service listening address" "3x-ui Адрес прослушивания службы подписки")" "$SUB_LISTEN_ADDR")
    SUB_LISTEN_PORT=$(ask_with_default "$(localized_text "3x-ui 订阅服务端口" "3x-ui Subscription service port" "3x-ui Порт службы подписки")" "$SUB_LISTEN_PORT")
    SUB_URI_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "普通订阅路径前缀（不带客户端 Subscription，建议写 /sub/）" "Standard subscription path prefix (without client identifier; recommended: /sub/)" "Префикс обычной подписки (без идентификатора клиента; рекомендуется /sub/)")" "$SUB_URI_PATH")")
    CLASH_URI_PATH=$(normalize_path_prefix "$(ask_with_default "$(localized_text "Clash/Mihomo 订阅路径前缀（不带客户端 Subscription，建议写 /clash/）" "Clash/Mihomo subscription path prefix (without client identifier; recommended: /clash/)" "Префикс подписки Clash/Mihomo (без идентификатора клиента; рекомендуется /clash/)")" "$CLASH_URI_PATH")")

    is_valid_listen_addr "$PANEL_LISTEN_ADDR" || { echo -e "$(localized_text "${RED}❌ 面板监听地址无效：${PANEL_LISTEN_ADDR}${PLAIN}" "${RED}❌ The panel listening address is invalid: ${PANEL_LISTEN_ADDR}${PLAIN}" "${RED}❌ Неверный адрес прослушивания панели: ${PANEL_LISTEN_ADDR}.${PLAIN}")"; return 1; }
    is_valid_listen_addr "$SUB_LISTEN_ADDR" || { echo -e "$(localized_text "${RED}❌ 订阅监听地址无效：${SUB_LISTEN_ADDR}${PLAIN}" "${RED}❌ The subscription listening address is invalid: ${SUB_LISTEN_ADDR}${PLAIN}" "${RED}❌ Неверный адрес прослушивания подписки: ${SUB_LISTEN_ADDR}.${PLAIN}")"; return 1; }
    is_valid_port "$PANEL_LISTEN_PORT" || { echo -e "$(localized_text "${RED}❌ 面板端口无效：${PANEL_LISTEN_PORT}${PLAIN}" "${RED}❌ Invalid panel port: ${PANEL_LISTEN_PORT}${PLAIN}" "${RED}❌ Неверный порт панели: ${PANEL_LISTEN_PORT}.${PLAIN}")"; return 1; }
    is_valid_port "$SUB_LISTEN_PORT" || { echo -e "$(localized_text "${RED}❌ 订阅端口无效：${SUB_LISTEN_PORT}${PLAIN}" "${RED}❌ Invalid subscription port: ${SUB_LISTEN_PORT}${PLAIN}" "${RED}❌ Неверный порт подписки: ${SUB_LISTEN_PORT}.${PLAIN}")"; return 1; }
    is_valid_path_prefix "$PANEL_WEB_PATH" || { echo -e "$(localized_text "${RED}❌ 面板公网路径无效：${PANEL_WEB_PATH}${PLAIN}" "${RED}❌ The public path of the panel is invalid: ${PANEL_WEB_PATH}${PLAIN}" "${RED}❌ Неверный путь панели в публичной сети: ${PANEL_WEB_PATH}.${PLAIN}")"; return 1; }
    is_valid_path_prefix "$SUB_URI_PATH" || { echo -e "$(localized_text "${RED}❌ 普通订阅路径无效：${SUB_URI_PATH}${PLAIN}" "${RED}❌ The normal subscription path is invalid: ${SUB_URI_PATH}${PLAIN}" "${RED}❌ Неверный обычный путь подписки: ${SUB_URI_PATH}.${PLAIN}")"; return 1; }
    is_valid_path_prefix "$CLASH_URI_PATH" || { echo -e "$(localized_text "${RED}❌ Clash/Mihomo 路径无效：${CLASH_URI_PATH}${PLAIN}" "${RED}❌ Clash/Mihomo Invalid path: ${CLASH_URI_PATH}${PLAIN}" "${RED}❌ Clash/Mihomo Неверный путь: ${CLASH_URI_PATH}${PLAIN}")"; return 1; }
    if [[ "$PANEL_WEB_PATH" == "$SUB_URI_PATH" || "$PANEL_WEB_PATH" == "$CLASH_URI_PATH" || "$SUB_URI_PATH" == "$CLASH_URI_PATH" ]]; then
        echo -e "$(localized_text "${RED}❌ 面板路径、普通订阅路径、Clash/Mihomo 路径不能相同。${PLAIN}" "${RED}❌ The panel path, normal subscription path, and Clash/Mihomo path cannot be the same.${PLAIN}" "${RED}❌ Путь к панели, обычный путь подписки и путь Clash/Mihomo не могут совпадать.${PLAIN}")"
        return 1
    fi
    warn_if_public_bind "$(localized_text "3x-ui 面板" "3x-ui panel" "Панель 3x-ui")" "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT" || return 1
    warn_if_public_bind "$(localized_text "3x-ui 订阅服务" "3x-ui Subscription Service" "Служба подписки 3x-ui")" "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT" || return 1

    save_and_offer_reapply_sni_stack
}

edit_sni_stack_reality_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}修改 REALITY 本地监听与伪装 SNI${PLAIN}" "${BOLD}Modified REALITY local listeners and disguise SNI${PLAIN}" "${BOLD}модифицированный REALITY локальный прослушивание и маскировка SNI${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "$(localized_text "${YELLOW}适用于：你在 3x-ui+Reality 入站中修改了监听端口、监听地址，或更换了伪装 SNI。${PLAIN}" "${YELLOW}Applies when you changed the listen port, listen address, or camouflage SNI of a 3x-ui+Reality inbound.${PLAIN}" "${YELLOW}Применяется, если вы изменили порт или адрес прослушивания либо маскировочный SNI входящего 3x-ui+Reality.${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "当前 REALITY：${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}" "Current REALITY: ${XRAY_LISTEN_ADDR}: ${XRAY_LISTEN_PORT}" "Текущий REALITY: ${XRAY_LISTEN_ADDR}: ${XRAY_LISTEN_PORT}")"
    echo -e "$(localized_text "当前 REALITY SNI：${REALITY_SNI}" "Current REALITY SNI: ${REALITY_SNI}" "Текущий REALITY SNI: ${REALITY_SNI}")"
    echo -e "------------------------------------------------"

    local reality_sni_input
    XRAY_LISTEN_ADDR=$(ask_with_default "$(localized_text "Xray / 3x-ui+Reality 入站本地监听地址" "Xray / 3x-ui+Reality inbound local listening address" "Локальный адрес прослушивания входящего Xray / 3x-ui+Reality")" "$XRAY_LISTEN_ADDR")
    XRAY_LISTEN_PORT=$(ask_with_default "$(localized_text "Xray / 3x-ui+Reality 入站本地监听端口" "Xray / 3x-ui+Reality inbound local listening port" "Локальный порт прослушивания входящего Xray / 3x-ui+Reality")" "$XRAY_LISTEN_PORT")
    reality_sni_input=$(ask_with_default "$(localized_text "REALITY 伪装 SNI" "REALITY disguise SNI" "Маскировка REALITY SNI")" "$REALITY_SNI")
    REALITY_SNI=$(normalize_domain_input "$reality_sni_input")

    is_valid_listen_addr "$XRAY_LISTEN_ADDR" || { echo -e "$(localized_text "${RED}❌ REALITY 监听地址无效：${XRAY_LISTEN_ADDR}${PLAIN}" "${RED}❌ REALITY The listening address is invalid: ${XRAY_LISTEN_ADDR}${PLAIN}" "${RED}❌ REALITY Неверный адрес прослушивания: ${XRAY_LISTEN_ADDR}${PLAIN}")"; return 1; }
    is_valid_port "$XRAY_LISTEN_PORT" || { echo -e "$(localized_text "${RED}❌ REALITY 端口无效：${XRAY_LISTEN_PORT}${PLAIN}" "${RED}❌ REALITY Invalid port: ${XRAY_LISTEN_PORT}${PLAIN}" "${RED}❌ REALITY Неверный порт: ${XRAY_LISTEN_PORT}${PLAIN}")"; return 1; }
    is_valid_domain "$REALITY_SNI" || { print_domain_validation_error "REALITY SNI" "$reality_sni_input" "$REALITY_SNI"; return 1; }
    [[ "$REALITY_SNI" == "$PANEL_DOMAIN" ]] && { echo -e "$(localized_text "${RED}❌ REALITY SNI 不能写面板域名。${PLAIN}" "${RED}❌ REALITY SNI The panel domain cannot be written.${PLAIN}" "${RED}❌ REALITY SNI Невозможно записать доменное имя панели.${PLAIN}")"; return 1; }
    local existing
    for existing in "${SITE_DOMAINS[@]}" "${TCP_ROUTE_SNIS[@]}" "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$REALITY_SNI" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ REALITY SNI 不能和其他 443 分流域名相同：${existing}${PLAIN}" "${RED}❌ REALITY SNI cannot be the same as other 443 routing domains: ${existing}${PLAIN}" "${RED}❌ REALITY SNI не может совпадать с другими именами доменов маршрутизация 443: ${existing}${PLAIN}")"; return 1; }
    done
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    probe_reality_sni "$REALITY_SNI" || return 1

    save_and_offer_reapply_sni_stack
}

edit_sni_stack_entry_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}修改 443 入口 / Web 反代监听${PLAIN}" "${BOLD}Modified 443 entry / Web reverse proxy listening${PLAIN}" "${BOLD}модифицированный вход 443 / прослушивание обратного веб-прокси${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    local web_label
    web_label=$(web_proxy_engine_label)
    echo -e "$(localized_text "${YELLOW}适用于：你要调整公网入口端口、Web 反代本地 TLS 端口，或修正监听地址。普通用户建议保持默认。${PLAIN}" "${YELLOW}Suitable for: you want to adjust the public entry port, Web reverse local TLS port, or modify the listening address. Ordinary users are advised to keep the default setting.${PLAIN}" "${YELLOW}подходит для: вы хотите настроить порт входа в публичную сеть, обратный локальный веб-порт TLS или изменить адрес прослушивания. Обычным пользователям рекомендуется сохранить настройки по умолчанию.${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "当前公网入口：${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT}" "Current public entry: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT}" "Текущий вход в публичную сеть: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT}.")"
    echo -e "$(localized_text "当前 ${web_label} 本地 TLS：${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}" "Current ${web_label} Local TLS:${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}" "Текущий ${web_label} Локальный TLS:${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}")"
    echo -e "------------------------------------------------"

    NGINX_LISTEN_ADDR=$(ask_with_default "$(localized_text "Nginx 公网监听地址" "Nginx public listening address" "Nginx адрес прослушивания публичной сети")" "$NGINX_LISTEN_ADDR")
    NGINX_LISTEN_PORT=$(ask_with_default "$(localized_text "Nginx 公网监听端口" "Nginx public listening port" "Порт прослушивания публичной сети Nginx")" "$NGINX_LISTEN_PORT")
    CADDY_LISTEN_ADDR=$(ask_with_default "$(localized_text "${web_label}监听地址" "${web_label} listening address" "Адрес прослушивания ${web_label}")" "$CADDY_LISTEN_ADDR")
    CADDY_LISTEN_PORT=$(ask_with_default "$(localized_text "${web_label}监听端口" "${web_label} listening port" "Порт прослушивания ${web_label}")" "$CADDY_LISTEN_PORT")

    is_valid_listen_addr "$NGINX_LISTEN_ADDR" || { echo -e "$(localized_text "${RED}❌ Nginx 监听地址无效：${NGINX_LISTEN_ADDR}${PLAIN}" "${RED}❌ Nginx The listening address is invalid: ${NGINX_LISTEN_ADDR}${PLAIN}" "${RED}❌ Nginx Неверный адрес прослушивания: ${NGINX_LISTEN_ADDR}${PLAIN}")"; return 1; }
    is_valid_listen_addr "$CADDY_LISTEN_ADDR" || { echo -e "$(localized_text "${RED}❌ Web 反代监听地址无效：${CADDY_LISTEN_ADDR}${PLAIN}" "${RED}❌ Web reverse proxy listening address is invalid: ${CADDY_LISTEN_ADDR}${PLAIN}" "${RED}❌ Недопустимый адрес прослушивания веб-прокси: ${CADDY_LISTEN_ADDR}.${PLAIN}")"; return 1; }
    is_valid_port "$NGINX_LISTEN_PORT" || { echo -e "$(localized_text "${RED}❌ Nginx 端口无效：${NGINX_LISTEN_PORT}${PLAIN}" "${RED}❌ Nginx Invalid port: ${NGINX_LISTEN_PORT}${PLAIN}" "${RED}❌ Nginx Неверный порт: ${NGINX_LISTEN_PORT}${PLAIN}")"; return 1; }
    is_valid_port "$CADDY_LISTEN_PORT" || { echo -e "$(localized_text "${RED}❌ Web 反代端口无效：${CADDY_LISTEN_PORT}${PLAIN}" "${RED}❌ Web reverse proxy port is invalid: ${CADDY_LISTEN_PORT}${PLAIN}" "${RED}❌ Неверный порт веб-прокси: ${CADDY_LISTEN_PORT}.${PLAIN}")"; return 1; }
    warn_if_public_bind "$web_label" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    if [[ "$NGINX_LISTEN_PORT" != "443" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️  Nginx 公网入口不是 443。请确认云安全组、防火墙和客户端地址都同步改了。${PLAIN}" "${YELLOW}⚠️ Nginx The public entry is not 443. Please confirm that the cloud security group, firewall and client address have all been changed simultaneously.${PLAIN}" "${YELLOW}⚠️ Nginx Вход в публичную сеть не 443. Подтвердите, что группа безопасности облака, брандмауэр и адрес клиента были изменены одновременно.${PLAIN}")"
    fi

    save_and_offer_reapply_sni_stack
}

edit_sni_stack_panel_domain_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}修改面板域名${PLAIN}" "${BOLD}Modify the panel domain${PLAIN}" "${BOLD}Измените доменное имя панели.${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    if [[ ! -f "$cf_env_file" ]]; then
        echo -e "$(localized_text "${RED}❌ 未找到 Cloudflare Token，请先到证书维护菜单更新 Token。${PLAIN}" "${RED}❌ Cloudflare Token was not found. Please go to the certificate maintenance menu to update the token first.${PLAIN}" "${RED}❌ Cloudflare Токен не найден. Пожалуйста, перейдите в меню обслуживания сертификатов, чтобы сначала обновить токен.${PLAIN}")"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$cf_env_file"
    if [[ -z "${CF_Token:-}" ]]; then
        echo -e "$(localized_text "${RED}❌ Cloudflare Token 为空，请先到证书维护菜单更新。${PLAIN}" "${RED}❌ Cloudflare Token is empty, please go to the certificate maintenance menu to update it first.${PLAIN}" "${RED}❌ Cloudflare Токен пуст. Сначала перейдите в меню обслуживания сертификата, чтобы обновить его.${PLAIN}")"
        return 1
    fi

    local old_domain new_domain new_domain_input existing confirm old_conf
    old_domain="$PANEL_DOMAIN"
    echo -e "$(localized_text "当前面板域名：${old_domain}" "Current panel domain: ${old_domain}" "Доменное имя текущей панели: ${old_domain}.")"
    echo -e "$(localized_text "${YELLOW}修改前请先把新域名解析到当前 VPS，并确认 Cloudflare Token 有该 zone 权限。${PLAIN}" "${YELLOW}Before modifying , please resolve the new domain to the current VPS and confirm that Cloudflare Token has the zone permission.${PLAIN}" "${YELLOW}Прежде чем изменять , разрешите новое доменное имя текущему VPS и подтвердите, что токен Cloudflare имеет разрешение зоны.${PLAIN}")"
    new_domain_input=$(ask_with_default "$(localized_text "新的面板域名" "New panel domain" "Новое доменное имя панели")" "$PANEL_DOMAIN")
    new_domain=$(normalize_domain_input "$new_domain_input")
    [[ "$new_domain" == "$old_domain" ]] && { echo -e "$(localized_text "${BLUE}面板域名未变化。${PLAIN}" "${BLUE}The panel domain has not changed.${PLAIN}" "${BLUE}Доменное имя панели не изменилось.${PLAIN}")"; return 0; }
    is_valid_domain "$new_domain" || { print_domain_validation_error "$(localized_text "面板域名" "Panel domain" "Доменное имя панели")" "$new_domain_input" "$new_domain"; return 1; }
    [[ "$new_domain" == "$REALITY_SNI" ]] && { echo -e "$(localized_text "${RED}❌ 面板域名不能和 REALITY SNI 相同。${PLAIN}" "${RED}❌ The panel domain cannot be the same as REALITY SNI.${PLAIN}" "${RED}❌ Доменное имя панели не может совпадать с REALITY SNI.${PLAIN}")"; return 1; }
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$new_domain" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 面板域名不能和网站/反代域名相同。${PLAIN}" "${RED}❌ The panel domain cannot be the same as the website/reverse proxy domain.${PLAIN}" "${RED}❌ Доменное имя панели не может совпадать с именем домена веб-сайта/обратного прокси-сервера.${PLAIN}")"; return 1; }
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$new_domain" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 面板域名不能和 TCP/SNI 入站域名相同。${PLAIN}" "${RED}The ❌ panel domain cannot be the same as the TCP/SNI inbound domain.${PLAIN}" "${RED}Доменное имя панели ❌ не может совпадать с именем входящего домена TCP/SNI.${PLAIN}")"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$new_domain" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 面板域名不能和 Xray 入站域名相同。${PLAIN}" "${RED}The ❌ panel domain cannot be the same as the Xray inbound domain.${PLAIN}" "${RED}Доменное имя панели ❌ не может совпадать с именем входящего домена Xray.${PLAIN}")"; return 1; }
    done
    check_domain_dns_sanity "$new_domain" "$(localized_text "新的面板域名" "New panel domain" "Новое доменное имя панели")" "prompt" || return 1
    confirm_risk_action "$(localized_text "替换 443 面板域名为 ${new_domain}" "Replace the 443 panel domain with ${new_domain}" "Замените доменное имя панели 443 на ${new_domain}.")" \
        "$(localized_text "面板域名、证书和 Caddy/Nginx 相关配置" "Panel domain, certificate and Caddy/Nginx related configuration" "Доменное имя панели, сертификат и конфигурация, связанная с Caddy/Nginx.")" \
        "$(localized_text "使用 443端口复用备份恢复旧域名配置" "Use Port 443 Reuse backup to restore the old domain configuration" "Восстановите старую конфигурацию доменного имени с помощью резервной копии повторного использования порта 443.")" \
        "$(localized_text "确认新域名 DNS 已解析到当前 VPS，且 Token 有该 zone 权限。" "Confirm that the new domain DNS has been resolved to the current VPS, and the Token has the zone permissions." "Убедитесь, что новое доменное имя DNS разрешено текущему VPS, а токен имеет разрешения зоны.")" || return 1

    issue_and_install_cert_for_domain "$new_domain" "$CF_Token" || return 1
    update_xui_panel_domain_settings_for_single_443 "$old_domain" "$new_domain" || return 1
    old_conf="/etc/caddy/conf.d/${old_domain}.caddy"
    [[ -f "$old_conf" ]] && quarantine_path "$old_conf" "/etc/caddy/conf.d_quarantine" >/dev/null 2>&1 || true
    PANEL_DOMAIN="$new_domain"
    rename_sni_ip_whitelist_domain "$old_domain" "$new_domain"
    save_and_offer_reapply_sni_stack
}

edit_sni_stack_runtime_profile() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}🧭 修改 443 分流参数${PLAIN}" "${BOLD}🧭 Modify 443 routing parameters${PLAIN}" "${BOLD}🧭 Изменение 443 параметров маршрутизации${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}用途：后续修改面板端口/路径、订阅端口/路径、REALITY SNI、入口端口时使用。${PLAIN}" "${YELLOW}Purpose: Used when subsequently modifying the panel port/path, subscription port/path, REALITY, SNI, and entry port.${PLAIN}" "${YELLOW}Назначение: используется при последующем изменении порта/пути панели, порта/пути подписки, REALITY, SNI и входного порта.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}修改面板域名请走主菜单 [19 443端口复用管理中心] -> [8 管理 Web 域名/反代] -> [9 修改面板域名]。${PLAIN}" "${YELLOW}To modify the panel domain, please go to the main menu [19 Port 443 Reuse Manager] -> [8 Manage Web domain/Reverse Proxy] -> [9 Modify Panel domain].${PLAIN}" "${YELLOW}Чтобы изменить имя домена панели, перейдите в главное меню [19 Управление повторным использованием порта 443] -> [8 Управление именем веб-домена/обратным прокси] -> [9 Изменить имя домена панели].${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}新增网站请走 [19] -> [8]，不用重跑首次配置。${PLAIN}" "${YELLOW}Please go to [19] -> [8] to add a new website. There is no need to rerun the first configuration.${PLAIN}" "${YELLOW}Пожалуйста, перейдите в [19] -> [8], чтобы добавить новый веб-сайт. Нет необходимости повторно запускать первую конфигурацию.${PLAIN}")"
        echo -e "------------------------------------------------"
        if load_sni_stack_env >/dev/null 2>&1; then
            print_sni_stack_current_summary
        else
            echo -e "$(localized_text "${RED}未找到 443 配置，请先运行 [19] -> [2]。${PLAIN}" "${RED}443 configuration not found, please run [19] -> [2] first.${PLAIN}" "${RED}Конфигурация 443 не найдена, сначала запустите [19] -> [2].${PLAIN}")"
            return 1
        fi
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 修改面板/订阅端口与路径${PLAIN}" "${GREEN}1. Modify the panel/subscription port and path${PLAIN}" "${GREEN}1. Измените порт панели/подписки и путь.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 修改 REALITY 本地监听 / 伪装 SNI${PLAIN}" "${GREEN}2. Modify REALITY local listeners/disguise SNI${PLAIN}" "${GREEN}2. Изменить REALITY локальный прослушивание/маскировку SNI${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 修改 Nginx 公网入口 / Web 反代本地 TLS${PLAIN}" "${GREEN}3. Modify Nginx public entry/Web to replace local TLS${PLAIN}" "${GREEN}3. Измените Nginx вход в публичную сеть/Интернет для замены локального TLS.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}  4. 修改面板域名：请走 [8] -> [9]${PLAIN}" "${YELLOW}4. Modify the panel domain: please go [8] -> [9]${PLAIN}" "${YELLOW}4. Измените доменное имя панели: выберите [8] -> [9].${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 重新应用当前保存的配置${PLAIN}" "${GREEN}5. Reapply the currently saved configuration${PLAIN}" "${GREEN}5. Повторно примените текущую сохраненную конфигурацию.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "$(localized_text "👉 请输入菜单编号或 ?: " "👉 Please enter menu number or ?:" "👉 Пожалуйста, введите номер меню или ?:")"
        case "$choice" in
            1) edit_sni_stack_panel_subscription_profile ;;
            2) edit_sni_stack_reality_profile ;;
            3) edit_sni_stack_entry_profile ;;
            4) echo -e "$(localized_text "${YELLOW}请使用：主菜单 [19 443端口复用管理中心] -> [8 管理 Web 域名/反代] -> [9 修改面板域名]。${PLAIN}" "${YELLOW}Please use: Main menu [19 Port 443 Reuse Manager] -> [8 Manage Web domain/Reverse Proxy] -> [9 Modify Panel domain].${PLAIN}" "${YELLOW}Используйте: Главное меню [19 Управление повторным использованием порта 443] -> [8 Управление именем веб-домена/обратным прокси-сервером] -> [9 Изменить имя домена панели].${PLAIN}")" ;;
            5) reapply_sni_stack_from_env ;;
            "?") show_sni_help; pause_return; continue ;;
            0) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择，请输入菜单编号或 ?。${PLAIN}" "${RED}❌ Invalid selection, please enter the menu number or ?.${PLAIN}" "${RED}❌ Неверный выбор, введите номер меню или ?.${PLAIN}")"; sleep 1 ;;
        esac
        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}

reapply_sni_stack_from_env() {
    load_sni_stack_env || return 1
    if [[ "${1:-}" != "--yes" ]]; then
        print_sni_stack_preview || return 1
    fi
    reapply_current_entry_mode --yes
}
