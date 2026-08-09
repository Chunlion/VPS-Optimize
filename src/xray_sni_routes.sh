# shellcheck shell=bash
# Xray SNI route records and sync workflows for nginx-stream/tcp-peek modes.

xray_sni_routes_fallback_notice() {
    echo -e "$(localized_text "${YELLOW}当前为 Xray Fallback 模式。${PLAIN}" "${YELLOW}Xray Fallback mode is active.${PLAIN}" "${YELLOW}Активен режим Xray Fallback.${PLAIN}")"
    print_xray_fallback_mode_explanation
}

list_xray_sni_routes() {
    load_sni_stack_env || return 1
    local mode fallback_idx
    mode=$(get_entry_mode)
    fallback_idx=$(xray_fallback_main_route_index 2>/dev/null || true)
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}Xray 入站分流规则${PLAIN}" "${BOLD}Xray Inbound routing rule${PLAIN}" "${BOLD}Правила маршрутизации входящих подключений Xray${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "配置文件：$(xray_sni_routes_path)" "Configuration file: $(xray_sni_routes_path)" "Файл конфигурации: $(xray_sni_routes_path).")"
    echo -e "$(localized_text "规则格式：SNI|ADDR|PORT" "Rule format: SNI|ADDR|PORT" "Формат правила: SNI|ADDR|PORT.")"
    if [[ "$mode" == "xray-fallback" ]]; then
        echo -e "------------------------------------------------"
        xray_sni_routes_fallback_notice
        print_xray_fallback_main_route_summary
    fi
    echo -e "------------------------------------------------"
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有 Xray 入站分流规则。${PLAIN}" "${YELLOW}Currently does not have the Xray inbound routing rule.${PLAIN}" "${YELLOW}в настоящее время не имеет правила маршрутизация входящего подключения Xray.${PLAIN}")"
        if [[ -n "${XRAY_LISTEN_PORT:-}" ]]; then
            echo -e "$(localized_text "${CYAN}旧默认 Xray/REALITY 后端仍是：${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}${PLAIN}" "${CYAN}Old default Xray/REALITY backend is still: ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}${PLAIN}" "${CYAN}старая версия по умолчанию Xray/REALITY по-прежнему: ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}${PLAIN}")"
            echo -e "$(localized_text "${CYAN}如需多个本地 Xray 入站，可按 SNI 添加新的本地端口分流记录。${PLAIN}" "${CYAN}If requires multiple local Xray inbounds, press SNI to add a new local port offload record.${PLAIN}" "${CYAN}Если для требуется несколько локальных входящих вызовов Xray, нажмите SNI, чтобы добавить новую запись о разгрузке локального порта.${PLAIN}")"
        fi
        return 0
    fi

    local i num
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        if [[ "$mode" == "xray-fallback" && -n "$fallback_idx" && "$i" == "$fallback_idx" ]]; then
            echo -e "$(localized_text "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]} ${GREEN}[xray-fallback 主入站，当前模式生效]${PLAIN}" "${GREEN}${num}. ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]} [xray-fallback main inbound, current mode takes effect]${PLAIN}" "${GREEN}${num}. ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]} [xray-резервный основной входящий режим, текущий режим вступает в силу]${PLAIN}")"
        elif [[ "$mode" == "xray-fallback" ]]; then
            echo -e "$(localized_text "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]} ${YELLOW}[已保留，当前 xray-fallback 模式下不生效]${PLAIN}" "${GREEN}${num}. ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]} [Reserved, not valid in current xray-fallback mode]${PLAIN}" "${GREEN}${num}. ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]} [Зарезервировано, недействительно в текущем резервном режиме xray]${PLAIN}")"
        else
            echo -e "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]}"
        fi
    done
}

add_xray_sni_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}添加 Xray 入站分流规则${PLAIN}" "${BOLD}Adds Xray inbound connection routing rule${PLAIN}" "${BOLD}добавляет правило входящей рассылки Xray${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "$(localized_text "${YELLOW}本菜单只记录 SNI -> 本地地址:端口；用于当前支持的端口复用模式渲染分流规则，不会创建、删除或修改 3x-ui/Xray 入站内部配置。${PLAIN}" "${YELLOW}This menu only records SNI -> local address: port; used for the currently supported Port 443 Reuse mode rendering routing rules, and will not create, delete or modify the internal configuration of the 3x-ui/Xray inbound connection.${PLAIN}" "${YELLOW}Это меню записывает только SNI -> локальный адрес: порт; используется для поддерживаемых в настоящее время правил маршрутизации в режиме повторного использования порта 443 и не будет создавать, удалять или изменять внутреннюю конфигурацию входящего соединения 3x-ui/Xray.${PLAIN}")"
    echo -e "------------------------------------------------"

    local route_sni route_sni_input route_addr route_port existing idx
    read_trimmed route_sni_input "$(localized_text "SNI/域名: " "SNI/domain:" "SNI/доменное имя:")"
    route_sni=$(normalize_domain_input "$route_sni_input")
    if [[ -z "$route_sni" || "$route_sni" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消添加。${PLAIN}" "${BLUE}Has been canceled.${PLAIN}" "${BLUE}отменен.${PLAIN}")"
        return 0
    fi
    is_valid_domain "$route_sni" || { print_domain_validation_error "$(localized_text "SNI/域名" "SNI/domain" "SNI/доменное имя")" "$route_sni_input" "$route_sni"; return 1; }
    if [[ "$route_sni" == "$PANEL_DOMAIN" || "$route_sni" == "$REALITY_SNI" ]]; then
        echo -e "$(localized_text "${RED}❌ Xray 入站域名不能和面板域名或 REALITY SNI 相同。${PLAIN}" "${RED}❌ The Xray inbound domain cannot be the same as the panel domain or REALITY SNI.${PLAIN}" "${RED}❌ Имя входящего домена Xray не может совпадать с именем домена панели или REALITY SNI.${PLAIN}")"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 该域名已作为 Web 域名使用，Xray 入站规则必须和 Web 域名分开。${PLAIN}" "${RED}❌ This domain is already used as a web domain. The Xray inbound rule must be separated from the web domain.${PLAIN}" "${RED}❌ Это доменное имя уже используется в качестве имени веб-домена. Правило для входящего подключения Xray должно быть отделено от имени веб-домена.${PLAIN}")"; return 1; }
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 该域名已存在于旧 TCP/SNI 本地入站规则中。${PLAIN}" "${RED}❌ This domain already exists in the old TCP/SNI local inbound rule.${PLAIN}" "${RED}❌ Это доменное имя уже существует в старом локальном входящем правиле TCP/SNI.${PLAIN}")"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "$(localized_text "${RED}❌ 该 Xray 入站分流规则已经存在。${PLAIN}" "${RED}❌ The Xray inbound offload rule already exists.${PLAIN}" "${RED}❌ Правило входящей разгрузки Xray уже существует.${PLAIN}")"; return 1; }
    done

    route_addr=$(ask_with_default "$(localized_text "本地监听地址" "local listening address" "местный адрес прослушивания")" "127.0.0.1")
    route_addr=$(normalize_loopback_addr "$route_addr")
    route_port=$(ask_with_default "$(localized_text "本地监听端口" "local listening port" "локальный порт прослушивания")" "${XRAY_LISTEN_PORT:-1443}")
    is_loopback_listen_addr "$route_addr" || { echo -e "$(localized_text "${RED}❌ 为避免公网暴露，本地监听地址只允许 127.0.0.1、localhost 或 ::1。${PLAIN}" "${RED}❌ To avoid public exposure, the local listening address is only allowed to be 127.0.0.1, localhost or ::1.${PLAIN}" "${RED}❌ Чтобы избежать воздействия публичной сети, локальным адресом прослушивания может быть только 127.0.0.1, localhost или ::1.${PLAIN}")"; return 1; }
    is_valid_port "$route_port" || { echo -e "$(localized_text "${RED}❌ 本地监听端口无效：${route_port}${PLAIN}" "${RED}❌ The local listening port is invalid: ${route_port}${PLAIN}" "${RED}❌ Неверный локальный порт прослушивания: ${route_port}.${PLAIN}")"; return 1; }
    if [[ "$route_port" == "$CADDY_LISTEN_PORT" ]]; then
        echo -e "$(localized_text "${RED}❌ 该端口与 Web 反代引擎本地端口 ${CADDY_LISTEN_PORT} 冲突。${PLAIN}" "${RED}❌ This port conflicts with the Web reverse proxy engine local port ${CADDY_LISTEN_PORT}.${PLAIN}" "${RED}❌ Этот порт конфликтует с локальным портом ${CADDY_LISTEN_PORT} механизма веб-прокси.${PLAIN}")"
        return 1
    fi
    if [[ "$route_port" == "$NGINX_LISTEN_PORT" || "$route_port" == "$PANEL_LISTEN_PORT" || "$route_port" == "$SUB_LISTEN_PORT" ]]; then
        echo -e "$(localized_text "${RED}❌ 入站端口不能复用公网入口、面板或订阅服务端口。${PLAIN}" "${RED}❌ The inbound port cannot reuse the public entry, panel or subscription service port.${PLAIN}" "${RED}❌ Входящий порт не может повторно использовать порт входа в публичную сеть, панель или порт службы подписки.${PLAIN}")"
        return 1
    fi
    existing=$(xray_sni_route_port_conflict "$route_addr" "$route_port" || true)
    if [[ -n "$existing" ]]; then
        echo -e "$(localized_text "${RED}❌ ${route_addr}:${route_port} 已被规则 ${existing} 使用。${PLAIN}" "${RED}❌ ${route_addr}:${route_port} is already used by rule ${existing}.${PLAIN}" "${RED}❌ ${route_addr}:${route_port} уже используется правилом ${existing}.${PLAIN}")"
        return 1
    fi

    print_xray_route_port_status "$route_sni" "$route_addr" "$route_port"
    if [[ -z "$(xray_route_listen_line_by_addr_port "$route_addr" "$route_port")" ]]; then
        echo -e "$(localized_text "${RED}❌ 端口未监听，请先去 3x-ui 创建并启用对应入站。${PLAIN}" "${RED}Port ❌ is not listening. Please go to 3x-ui to create and enable the corresponding inbound port first.${PLAIN}" "${RED}Порт ❌ не прослушивается. Пожалуйста, перейдите к 3x-ui, чтобы сначала создать и включить соответствующий входящий порт.${PLAIN}")"
        return 1
    fi

    idx=${#XRAY_SNI_ROUTE_SNIS[@]}
    XRAY_SNI_ROUTE_SNIS[$idx]="$route_sni"
    XRAY_SNI_ROUTE_ADDRS[$idx]="$route_addr"
    XRAY_SNI_ROUTE_PORTS[$idx]="$route_port"
    save_xray_sni_route_arrays
    echo -e "$(localized_text "${GREEN}✅ 已保存 Xray 入站分流规则：${route_sni} -> ${route_addr}:${route_port}${PLAIN}" "${GREEN}✅ Saved Xray inbound routing rule: ${route_sni} -> ${route_addr}:${route_port}${PLAIN}" "${GREEN}✅ Правило маршрутизации входящего подключения Xray сохранено: ${route_sni} -> ${route_addr}:${route_port}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}提示：保存后需要执行“同步到当前入口模式”或重新应用当前入口模式，公网 443 才会使用新规则。${PLAIN}" "${YELLOW}After saving, sync or reapply the current entry mode before public port 443 uses the new rule.${PLAIN}" "${YELLOW}После сохранения синхронизируйте или повторно примените текущий режим входа, чтобы публичный порт 443 использовал новое правило.${PLAIN}")"
}

remove_xray_sni_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}删除 Xray 入站分流规则${PLAIN}" "${BOLD}Delete Xray inbound routing rule${PLAIN}" "${BOLD}удалить правило маршрутизация входящего подключения Xray${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有可删除的 Xray 入站分流规则。${PLAIN}" "${YELLOW}There are currently no Xray inbound routing rules that can be deleted.${PLAIN}" "${YELLOW}В настоящее время нет правил маршрутизация входящего подключения Xray, которые можно удалить.${PLAIN}")"
        return 0
    fi

    local i num choice idx route_sni
    local -a new_snis=() new_addrs=() new_ports=()
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "$(localized_text "请输入要删除的序号: " "Please enter the serial number to be deleted:" "Пожалуйста, введите серийный номер, который необходимо удалить:")"
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消删除。${PLAIN}" "${BLUE}Has been canceled.${PLAIN}" "${BLUE}отменен.${PLAIN}")"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#XRAY_SNI_ROUTE_SNIS[@]} )); then
        echo -e "$(localized_text "${RED}❌ 序号无效。${PLAIN}" "${RED}❌ The serial number is invalid.${PLAIN}" "${RED}❌ Серийный номер недействителен.${PLAIN}")"
        return 1
    fi

    idx=$((choice - 1))
    route_sni="${XRAY_SNI_ROUTE_SNIS[$idx]}"
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_snis+=("${XRAY_SNI_ROUTE_SNIS[$i]}")
        new_addrs+=("${XRAY_SNI_ROUTE_ADDRS[$i]}")
        new_ports+=("${XRAY_SNI_ROUTE_PORTS[$i]}")
    done
    XRAY_SNI_ROUTE_SNIS=("${new_snis[@]}")
    XRAY_SNI_ROUTE_ADDRS=("${new_addrs[@]}")
    XRAY_SNI_ROUTE_PORTS=("${new_ports[@]}")
    save_xray_sni_route_arrays
    echo -e "$(localized_text "${GREEN}✅ 已删除 Xray 入站分流规则：${route_sni}${PLAIN}" "${GREEN}✅ Deleted Xray inbound routing rule: ${route_sni}${PLAIN}" "${GREEN}✅ Правило маршрутизации входящего подключения Xray удалено: ${route_sni}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}提示：删除后需要执行“同步到当前入口模式”或重新应用当前入口模式。${PLAIN}" "${YELLOW}After deletion, sync or reapply the current entry mode.${PLAIN}" "${YELLOW}После удаления синхронизируйте или повторно примените текущий режим входа.${PLAIN}")"
}

check_xray_sni_route_ports() {
    load_sni_stack_env || return 1
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}检查 Xray 入站端口状态${PLAIN}" "${BOLD}Check Xray Inbound port status${PLAIN}" "${BOLD}Проверьте Xray Статус входящего порта${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前没有 Xray 入站分流规则。${PLAIN}" "${YELLOW}Currently does not have the Xray inbound routing rule.${PLAIN}" "${YELLOW}в настоящее время не имеет правила маршрутизация входящего подключения Xray.${PLAIN}")"
        return 0
    fi

    local i
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        print_xray_route_port_status "${XRAY_SNI_ROUTE_SNIS[$i]}" "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}"
        echo -e "------------------------------------------------"
    done
}

sync_xray_sni_routes_to_entry_mode() {
    load_sni_stack_env || return 1
    local mode
    mode=$(get_entry_mode)
    case "$mode" in
        "nginx-stream")
            echo -e "$(localized_text "${CYAN}正在同步 Xray 入站分流规则到 Nginx Stream 配置...${PLAIN}" "${CYAN}Is synchronizing Xray Inbound connection routing rules to Nginx Stream configuration...${PLAIN}" "${CYAN}синхронизирует правила входящей рассылки Xray с конфигурацией Nginx Stream...${PLAIN}")"
            reapply_sni_stack_from_env --yes
            ;;
        "tcp-peek")
            local tmp_config target_config
            echo -e "$(localized_text "${CYAN}正在同步 Xray 入站分流规则到 TCP Peek + Splice 配置...${PLAIN}" "${CYAN}Is synchronizing Xray Inbound connection routing rules to TCP Peek + Splice configuration...${PLAIN}" "${CYAN}синхронизирует правила входящей рассылки Xray с конфигурацией TCP Peek + Splice...${PLAIN}")"
            target_config=$(vpso_mux_config_path)
            tmp_config="${target_config}.tmp.$$"
            write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$tmp_config" || return 1
            if ! run_vpso_mux_config_check "$tmp_config"; then
                quarantine_path "$tmp_config" "/etc/vps-optimize/quarantine/vpso-mux" >/dev/null 2>&1 || true
                return 1
            fi
            mv "$tmp_config" "$target_config" || { echo -e "$(localized_text "${RED}❌ TCP Peek + Splice 配置替换失败：${target_config}${PLAIN}" "${RED}❌ TCP Peek + Splice Configuration replacement failed: ${target_config}${PLAIN}" "${RED}❌ TCP Peek + Splice Не удалось заменить конфигурацию: ${target_config}${PLAIN}")"; return 1; }
            if systemctl is-active --quiet vpso-mux 2>/dev/null; then
                systemctl restart vpso-mux || { print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"; echo -e "$(localized_text "${RED}❌ vpso-mux 重启失败，请查看上面的日志。${PLAIN}" "${RED}❌ vpso-mux Restart failed, please check the log above.${PLAIN}" "${RED}❌ vpso-mux Не удалось перезапустить, проверьте журнал выше.${PLAIN}")"; return 1; }
            else
                echo -e "$(localized_text "${YELLOW}vpso-mux 分流器当前未运行，已仅生成并校验配置文件。${PLAIN}" "${YELLOW}The vpso-mux routing is not currently running, only the configuration file has been generated and verified.${PLAIN}" "${YELLOW}маршрутизация vpso-mux в настоящее время не работает, только файл конфигурации создан и проверен.${PLAIN}")"
            fi
            echo -e "$(localized_text "${GREEN}✅ 已同步到 TCP Peek + Splice 配置：${target_config}${PLAIN}" "${GREEN}✅ Synced to TCP Peek + Splice Configuration: ${target_config}${PLAIN}" "${GREEN}✅ Синхронизирован с конфигурацией TCP Peek + Splice: ${target_config}${PLAIN}")"
            ;;
        "xray-fallback")
            xray_sni_routes_fallback_notice
            return 1
            ;;
        *)
            echo -e "$(localized_text "${RED}❌ 当前 ENTRY_MODE 无效或未配置：${mode}${PLAIN}" "${RED}❌ Current ENTRY_MODE is invalid or not configured: ${mode}${PLAIN}" "${RED}❌ Текущий ENTRY_MODE недействителен или не настроен: ${mode}${PLAIN}")"
            return 1
            ;;
    esac
}

manage_xray_inbound_routes() {
    load_sni_stack_env || return 1
    if [[ "$(get_entry_mode)" == "xray-fallback" ]]; then
        while true; do
            clear
            echo -e "${CYAN}================================================${PLAIN}"
            echo -e "$(localized_text "${BOLD}Xray 入站管理${PLAIN}" "${BOLD}Xray Inbound management${PLAIN}" "${BOLD}Управление входящими подключениями Xray${PLAIN}")"
            echo -e "${CYAN}================================================${PLAIN}"
            xray_sni_routes_fallback_notice
            print_xray_fallback_main_route_summary
            echo -e "------------------------------------------------"
            echo -e "$(localized_text "${GREEN}  1. 查看入站分流规则${PLAIN}" "${GREEN}1. View the inbound routing rule${PLAIN}" "${GREEN}1. Просмотреть правила маршрутизации входящих подключений${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}  2. 添加入站分流规则（当前模式不可用）${PLAIN}" "${YELLOW}2. Add inbound routing rules (not available in current mode)${PLAIN}" "${YELLOW}2. Добавьте правила маршрутизация входящего подключения (недоступно в текущем режиме)${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}  3. 删除入站分流规则（当前模式不可用）${PLAIN}" "${YELLOW}3. Delete inbound routing rules (not available in current mode)${PLAIN}" "${YELLOW}3. Удалить правила маршрутизации входящих подключений (недоступно в текущем режиме)${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}  4. 同步规则到当前入口模式（当前模式不可用）${PLAIN}" "${YELLOW}4. Synchronize rules to the current entry mode (the current mode is unavailable)${PLAIN}" "${YELLOW}4. Синхронизировать правила с текущим режимом входа (текущий режим недоступен)${PLAIN}")"
            echo -e "------------------------------------------------"
            echo -e "$(localized_text "${RED}  0. 返回 / q 返回${PLAIN}" "${RED}0. Return / q Return${PLAIN}" "${RED}0. Возврат / q Возврат${PLAIN}")"
            echo -e "${CYAN}================================================${PLAIN}"

            local fallback_choice
            read_trimmed fallback_choice "$(localized_text "请选择操作: " "Please select an action:" "Пожалуйста, выберите действие:")"
            case "$fallback_choice" in
                1) list_xray_sni_routes ;;
                2|3|4)
                    echo -e "$(localized_text "${YELLOW}当前为 xray-fallback 模式，Xray 入站管理默认不可新增、删除或同步规则。${PLAIN}" "${YELLOW}xray-fallback mode is active; Xray inbound rules cannot be added, deleted, or synchronized here.${PLAIN}" "${YELLOW}Активен режим xray-fallback; здесь нельзя добавлять, удалять или синхронизировать правила входящих подключений Xray.${PLAIN}")"
                    echo -e "$(localized_text "${YELLOW}如需多个本地 Xray 入站通过 443 按 SNI 分流，请切换到 nginx-stream 或 tcp-peek。${PLAIN}" "${YELLOW}If multiple local Xray inbound pass 443 split by SNI, please switch to nginx-stream or tcp-peek.${PLAIN}" "${YELLOW}Если несколько локальных входящих каналов Xray 443 разделены на SNI, переключитесь на nginx-stream или tcp-peek.${PLAIN}")"
                    ;;
                0|q|Q) break ;;
                *) echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")" ;;
            esac
            echo ""
            read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        done
        return 0
    fi

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}Xray 入站管理${PLAIN}" "${BOLD}Xray Inbound management${PLAIN}" "${BOLD}Управление входящими подключениями Xray${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}只管理 SNI -> 本地地址:端口 分流记录，用于当前支持的端口复用模式渲染分流规则；不编辑 3x-ui/Xray 入站内部配置。${PLAIN}" "${YELLOW}Only manages the SNI -> local address:port routing record, which is used for the currently supported Port 443 Reuse mode rendering routing rules; it does not edit the 3x-ui/Xray inbound connection internal configuration.${PLAIN}" "${YELLOW}управляет только SNI -> локальный адрес: записи маршрутизирования порта, которые используются для поддерживаемых в настоящее время правил маршрутизирования рендеринга в однозаходном режиме; он не редактирует входящую внутреннюю конфигурацию 3x-ui/Xray.${PLAIN}")"
        echo -e "$(localized_text "配置文件：$(xray_sni_routes_path)" "Configuration file: $(xray_sni_routes_path)" "Файл конфигурации: $(xray_sni_routes_path).")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 查看入站分流规则${PLAIN}" "${GREEN}1. View the inbound routing rule${PLAIN}" "${GREEN}1. Просмотреть правила маршрутизации входящих подключений${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 添加入站分流规则${PLAIN}" "${GREEN}2. Add inbound routing rule${PLAIN}" "${GREEN}2. Добавить правило маршрутизации входящего подключения${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 删除入站分流规则${PLAIN}" "${GREEN}3. Delete the inbound routing rule${PLAIN}" "${GREEN}3. Удалить правило маршрутизации входящего подключения${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 检查入站端口状态${PLAIN}" "${GREEN}4. Check the inbound port status${PLAIN}" "${GREEN}4. Проверьте состояние входящего порта.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 同步到当前入口模式${PLAIN}" "${GREEN}5. Synchronize to the current entry mode${PLAIN}" "${GREEN}5. Синхронизироваться с текущим режимом входа${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回 / q 返回${PLAIN}" "${RED}0. Return / q Return${PLAIN}" "${RED}0. Возврат / q Возврат${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "$(localized_text "请选择操作: " "Please select an action:" "Пожалуйста, выберите действие:")"
        case "$choice" in
            1) list_xray_sni_routes ;;
            2) add_xray_sni_route ;;
            3) remove_xray_sni_route ;;
            4) check_xray_sni_route_ports ;;
            5) sync_xray_sni_routes_to_entry_mode ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")" ;;
        esac
        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}

manage_sni_stack_tcp_routes() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}Xray 入站管理${PLAIN}" "${BOLD}Xray Inbound management${PLAIN}" "${BOLD}Управление входящими подключениями Xray${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}用途：记录你已在 3x-ui/Xray 配好的本地入站：SNI -> 本地地址:端口。${PLAIN}" "${YELLOW}Purpose: record the local inbound you have configured in 3x-ui/Xray: SNI -> local address: port.${PLAIN}" "${YELLOW}Назначение: записать локальное входящее подключение, который вы настроили в 3x-ui/Xray: SNI -> локальный адрес: порт.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}这些记录用于当前支持的端口复用模式渲染分流规则；脚本不开放新端口，不改 3x-ui/Xray 入站内部配置。${PLAIN}" "${YELLOW}These records are used for the currently supported Port 443 Reuse mode rendering routing rules; the script does not open new ports and does not change the internal configuration of the 3x-ui/Xray inbound connection.${PLAIN}" "${YELLOW}Эти записи используются для поддерживаемых в настоящее время правил разгрузки рендеринга в режиме с повторным использованием порта 443; сценарий не открывает новые порты и не изменяет внутреннюю конфигурацию входящего подключения 3x-ui/Xray.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 查看当前 TCP/SNI 入站${PLAIN}" "${GREEN}1. View current TCP/SNI inbound${PLAIN}" "${GREEN}1. Просмотр текущего входящего TCP/SNI${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 新增 TCP/SNI 入站${PLAIN}" "${GREEN}2. Add TCP/SNI inbound${PLAIN}" "${GREEN}2. Добавьте входящий TCP/SNI.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 修改 TCP/SNI 入站${PLAIN}" "${GREEN}3. Modify TCP/SNI inbound${PLAIN}" "${GREEN}3. Изменить TCP/SNI входящий${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 删除 TCP/SNI 入站${PLAIN}" "${GREEN}4. Delete TCP/SNI inbound${PLAIN}" "${GREEN}4. Удалить TCP/SNI входящий${PLAIN}")"
        echo -e "$(localized_text "${BLUE}  5. 查看 Web 白名单适用范围${PLAIN}" "${BLUE}5. View the applicable scope of the Web whitelist${PLAIN}" "${BLUE}5. Просмотрите применимую область белого веб-списка.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  6. 重新应用并重启 Nginx/Caddy${PLAIN}" "${GREEN}6. Reapply and restart Nginx/Caddy${PLAIN}" "${GREEN}6. Повторно примените и перезапустите Nginx/Caddy.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  7. 443端口复用链路体检${PLAIN}" "${GREEN}7. Port 443 Reuse link health check${PLAIN}" "${GREEN}7. Проверка состояния повторного использования порта 443${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"
        case "$choice" in
            1) list_sni_stack_tcp_routes ;;
            2) add_sni_stack_tcp_route ;;
            3) edit_sni_stack_tcp_route ;;
            4) remove_sni_stack_tcp_route ;;
            5)
                echo -e "$(localized_text "${YELLOW}Web 白名单只适用于 Web 域名：面板、订阅、普通网站、面板域名和自定义反代域名。${PLAIN}" "${YELLOW}Web whitelist only applies to web domains: panel, subscription, ordinary website, panel domain and custom reverse proxy domain.${PLAIN}" "${YELLOW}Белый список Web применяется только к именам веб-доменов: панель, подписка, обычный веб-сайт, доменное имя панели и собственное доменное имя обратного прокси.${PLAIN}")"
                echo -e "$(localized_text "${YELLOW}TCP/SNI 入站和 Xray 节点流量不会启用 IP 白名单；如需限制来源，请在后端服务或防火墙侧单独设计。${PLAIN}" "${YELLOW}TCP/SNI inbound and Xray node traffic will not enable IP whitelisting; if you need to limit the source, please design it separately on the backend service or firewall side.${PLAIN}" "${YELLOW}входящее подключение TCP/SNI и трафик узла Xray не будут включать белый список IP-адресов; если вам нужно ограничить источник, спроектируйте его отдельно на стороне серверной службы или брандмауэра.${PLAIN}")"
                ;;
            6) reapply_sni_stack_from_env ;;
            7) sni_stack_health_check ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")" ;;
        esac
        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}

manage_sni_stack_ip_whitelist() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}🔐 443 域名 IP 白名单${PLAIN}" "${BOLD}🔐 443 domain IP Whitelist${PLAIN}" "${BOLD}🔐 443 Белый список доменных имен IP${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        load_sni_stack_env || return 1
        local whitelist_supported="yes"
        if ! web_proxy_engine_supports_web_whitelist "${ENTRY_MODE:-$(get_entry_mode)}" "${WEB_PROXY_ENGINE:-caddy}"; then
            whitelist_supported="no"
        fi
        echo -e "$(localized_text "${YELLOW}只限制你选择的 Web 域名；支持面板、订阅、网站/反代，Xray 入站、REALITY SNI 与未知 SNI 不受 Web 白名单影响。${PLAIN}" "${YELLOW}Only limits the web domain you choose; supports panel, subscription, website/reverse proxy, Xray inbound, REALITY SNI and unknown SNI are not affected by the web whitelist.${PLAIN}" "${YELLOW}ограничивает только выбранное вами имя веб-домена; поддерживает панель, подписку, веб-сайт/обратный прокси-сервер, входящее соединение Xray, REALITY SNI и неизвестный SNI не зависят от белого списка веб-сайтов.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}Nginx Stream/TCP Peek 入口会在入口层按 SNI + 源 IP 拦截，避免影响同入口其他服务。${PLAIN}" "${YELLOW}The Nginx Stream/TCP Peek entry will be intercepted at the entry layer by SNI + source IP to avoid affecting other services with the same entry.${PLAIN}" "${YELLOW}Вход Nginx Stream/TCP Peek будет перехвачен на входном уровне SNI + IP-адрес источника, чтобы не влиять на другие службы с тем же входом.${PLAIN}")"
        if [[ "$whitelist_supported" != "yes" ]]; then
            echo -e "$(localized_text "${RED}当前为 xray-fallback，本地 Web 反代引擎无法可靠获取真实客户端源 IP，禁止新增或覆盖 Web 白名单。${PLAIN}" "${RED}Is currently xray-fallback. The local Web reverse proxy engine cannot reliably obtain the real client source IP. It is prohibited to add or overwrite the Web whitelist.${PLAIN}" "${RED}в настоящее время является резервным xray. Локальный механизм веб-прокси не может надежно получить реальный исходный IP-адрес клиента. Запрещается добавлять или перезаписывать белый список веб-сайтов.${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}你仍可清除已有白名单；如需继续使用白名单，请切到 Nginx Stream/TCP Peek。${PLAIN}" "${YELLOW}You can still clear the existing whitelist; if you want to continue using the whitelist, please switch to Nginx Stream/TCP Peek.${PLAIN}" "${YELLOW}Вы по-прежнему можете очистить существующий белый список; если вы хотите продолжить использовать белый список, переключитесь на Nginx Stream/TCP Peek.${PLAIN}")"
        fi
        echo -e "------------------------------------------------"

        local -a domains=("$PANEL_DOMAIN")
        local -a labels=("$(localized_text "面板/订阅" "Panel/subscription" "Панель/подписка")")
        local site_domain i num domain current_ranges
        for site_domain in "${SITE_DOMAINS[@]}"; do
            [[ -z "$site_domain" ]] && continue
            domains+=("$site_domain")
            labels+=("$(localized_text "网站/反代" "Website/reverse proxy" "Сайт/обратный прокси")")
        done
        for i in "${!domains[@]}"; do
            num=$((i + 1))
            current_ranges=$(sni_ip_whitelist_ranges_for_domain "${domains[$i]}")
            if [[ -n "$current_ranges" ]]; then
                echo -e "$(localized_text "${GREEN}${num}.${PLAIN} [${labels[$i]}] ${domains[$i]}  ${YELLOW}仅允许：${current_ranges}${PLAIN}" "${GREEN}${num}. [${labels[$i]}] ${domains[$i]} Only allowed: ${current_ranges}${PLAIN}" "${GREEN}${num}. [${labels[$i]}] ${domains[$i]} Разрешено только: ${current_ranges}${PLAIN}")"
            else
                echo -e "$(localized_text "${GREEN}${num}.${PLAIN} [${labels[$i]}] ${domains[$i]}  ${BLUE}未启用${PLAIN}" "${GREEN}${num}. [${labels[$i]}] ${domains[$i]} is not enabled${PLAIN}" "${GREEN}${num}. [${labels[$i]}] ${domains[$i]} не включен${PLAIN}")"
            fi
        done
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}0. 返回上一级 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice idx action whitelist_input whitelist_ranges current_client_ip
        local -a whitelist_array=()
        read_trimmed choice "$(localized_text "请输入要管理的域名序号: " "Please enter the domain serial number to be managed:" "Пожалуйста, введите серийный номер доменного имени, которым нужно управлять:")"
        [[ "$choice" == "0" || -z "$choice" ]] && break
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#domains[@]} )); then
            echo -e "$(localized_text "${RED}❌ 序号无效。${PLAIN}" "${RED}❌ The serial number is invalid.${PLAIN}" "${RED}❌ Серийный номер недействителен.${PLAIN}")"
            pause_return
            continue
        fi

        idx=$((choice - 1))
        domain="${domains[$idx]}"
        current_ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        echo -e "$(localized_text "当前域名：${domain}" "Current domain: ${domain}" "Текущее доменное имя: ${domain}.")"
        echo -e "$(localized_text "当前白名单：${current_ranges:-未启用}" "Current whitelist: ${current_ranges:-未启用}" "Текущий белый список: ${current_ranges:-未启用}.")"
        echo -e "$(localized_text "1. 设置/覆盖白名单" "1. Set/override whitelist" "1. Установить/переопределить белый список")"
        echo -e "$(localized_text "2. 清除白名单" "2. Clear the whitelist" "2. Очистите белый список")"
        echo -e "$(localized_text "0/q. 取消" "0/q. Cancel" "0/кв. Отмена")"
        read_trimmed action "$(localized_text "请选择操作: " "Please select an action:" "Пожалуйста, выберите действие:")"
        case "$action" in
            1)
                if [[ "$whitelist_supported" != "yes" ]]; then
                    echo -e "$(localized_text "${RED}❌ 当前组合禁止设置 Web 白名单。请先切换入口模式或 Web 反代引擎。${PLAIN}" "${RED}❌ The current combination prohibits setting the Web whitelist. Please switch to entry mode or web reverse proxy engine first.${PLAIN}" "${RED}❌ Текущая комбинация запрещает настройку белого списка Интернета. Пожалуйста, сначала переключитесь в режим входа или в механизм веб-прокси.${PLAIN}")"
                    pause_return
                    continue
                fi
                current_client_ip=$(detect_ssh_client_ip)
                [[ -n "$current_client_ip" ]] && echo -e "$(localized_text "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}" "${YELLOW}The current source IP of SSH may be: ${current_client_ip}. Please confirm that it has been added to the whitelist.${PLAIN}" "${YELLOW}Текущий исходный IP-адрес SSH может быть: ${current_client_ip}. Пожалуйста, подтвердите, что он был добавлен в белый список.${PLAIN}")"
                read_trimmed whitelist_input "$(localized_text "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: " "Please enter the IP/CIDR that allows access to ${domain} (separate multiple by spaces or commas):" "Введите IP/CIDR, который разрешает доступ к ${domain} (разделяйте кратные пробелами или запятыми):")"
                if ! normalize_ip_whitelist_input "$whitelist_input" whitelist_array; then
                    echo -e "$(localized_text "${RED}❌ 白名单为空或格式错误，已取消。${PLAIN}" "${RED}❌ The whitelist is empty or has an incorrect format and has been cancelled.${PLAIN}" "${RED}❌ Белый список пуст или имеет неверный формат и был отменен.${PLAIN}")"
                    pause_return
                    continue
                fi
                append_vps_public_ips_to_whitelist whitelist_array
                whitelist_ranges=$(join_array_by_space "${whitelist_array[@]}")
                confirm_risk_action "$(localized_text "为 ${domain} 启用 IP 白名单" "Enable IP whitelisting for ${domain}" "Включить белый список IP-адресов для ${domain}")" \
                    "$(localized_text "443 入口层会仅对该 SNI 做源 IP 限制" "443 The entry layer will only restrict the source IP of SNI." "443 Входной уровень будет ограничивать только исходный IP-адрес SNI.")" \
                    "$(localized_text "使用 443端口复用自动备份回滚，或清除该域名白名单后重新应用" "Use the Port 443 Reuse to automatically back up and roll back, or clear the domain whitelist and reapply it." "Используйте автоматическое резервное копирование и откат повторного использования порта 443 или очистите белый список доменных имен и примените его повторно.")" \
                    "$(localized_text "确认你的管理 IP 已包含在白名单中，且该域名不是 Cloudflare 橙云代理访问。" "Confirm that your management IP is included in the whitelist and the domain is not Cloudflare Orange Cloud proxy access." "Убедитесь, что ваш IP-адрес управления включен в белый список, а имя домена не является Cloudflare для доступа к прокси-серверу Orange Cloud.")" || continue
                set_sni_ip_whitelist_for_domain "$domain" "$whitelist_ranges"
                save_and_offer_reapply_sni_stack
                ;;
            2)
                if [[ -z "$current_ranges" ]]; then
                    echo -e "$(localized_text "${BLUE}该域名未启用白名单。${PLAIN}" "${BLUE}This domain is not whitelisted.${PLAIN}" "${BLUE}Это доменное имя не внесено в белый список.${PLAIN}")"
                    pause_return
                    continue
                fi
                confirm_risk_action "$(localized_text "清除 ${domain} 的 IP 白名单" "Clear the IP whitelist of ${domain}" "Очистите белый список IP-адресов ${domain}.")" \
                    "$(localized_text "该域名会恢复为普通 443 分流访问" "The domain will be restored to normal 443 redirection access" "Для доменного имени будет восстановлен обычный доступ к перенаправлению 443.")" \
                    "$(localized_text "重新设置该域名白名单" "Reset the domain whitelist" "Сбросить белый список доменных имен")" \
                    "$(localized_text "确认这是你想要的公网访问策略。" "Confirm that this is the public access policy you want." "Подтвердите, что это именно та политика доступа к публичной сети, которая вам нужна.")" || continue
                remove_sni_ip_whitelist_for_domain "$domain"
                save_and_offer_reapply_sni_stack
                ;;
            0|q|Q|"")
                ;;
            *)
                echo -e "$(localized_text "${RED}❌ 无效操作。${PLAIN}" "${RED}❌ Invalid operation.${PLAIN}" "${RED}❌ Недопустимая операция.${PLAIN}")"
                pause_return
                ;;
        esac
    done
}
