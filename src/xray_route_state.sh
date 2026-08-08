# shellcheck shell=bash
# Xray SNI route persistence and local listener status helpers.

xray_sni_routes_path() {
    echo "/etc/vps-optimize/xray-sni-routes.conf"
}

load_xray_sni_route_arrays() {
    local route_file line sni addr port
    route_file=$(xray_sni_routes_path)
    XRAY_SNI_ROUTE_SNIS=()
    XRAY_SNI_ROUTE_ADDRS=()
    XRAY_SNI_ROUTE_PORTS=()

    [[ -f "$route_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        [[ -n "$(trim_input "$line")" ]] || continue
        IFS='|' read -r sni addr port _ <<< "$line"
        sni=$(normalize_domain_input "$sni")
        addr=$(normalize_loopback_addr "${addr:-127.0.0.1}")
        port="$(trim_input "${port:-}")"
        if is_valid_domain "$sni" && is_loopback_listen_addr "$addr" && is_valid_port "$port"; then
            XRAY_SNI_ROUTE_SNIS+=("$sni")
            XRAY_SNI_ROUTE_ADDRS+=("$addr")
            XRAY_SNI_ROUTE_PORTS+=("$port")
        fi
    done < "$route_file"
}

save_xray_sni_route_arrays() {
    local route_file i
    route_file=$(xray_sni_routes_path)
    mkdir -p "$(dirname "$route_file")"
    : > "$route_file"
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ -n "${XRAY_SNI_ROUTE_SNIS[$i]:-}" ]] || continue
        printf '%s|%s|%s\n' "${XRAY_SNI_ROUTE_SNIS[$i]}" "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}" >> "$route_file"
    done
    chmod 600 "$route_file" 2>/dev/null || true
}

xray_sni_route_index() {
    local sni="$1"
    local i
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$sni" == "${XRAY_SNI_ROUTE_SNIS[$i]}" ]] && { echo "$i"; return 0; }
    done
    return 1
}

xray_fallback_main_route_index() {
    local i
    if [[ -n "${XRAY_FALLBACK_MAIN_SNI:-}" ]]; then
        for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            [[ "$XRAY_FALLBACK_MAIN_SNI" == "${XRAY_SNI_ROUTE_SNIS[$i]}" ]] && { echo "$i"; return 0; }
        done
    fi
    if [[ -n "${XRAY_FALLBACK_MAIN_ADDR:-}" && -n "${XRAY_FALLBACK_MAIN_PORT:-}" ]]; then
        for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            if [[ "$XRAY_FALLBACK_MAIN_ADDR" == "${XRAY_SNI_ROUTE_ADDRS[$i]}" && "$XRAY_FALLBACK_MAIN_PORT" == "${XRAY_SNI_ROUTE_PORTS[$i]}" ]]; then
                echo "$i"
                return 0
            fi
        done
    fi
    if [[ "$(get_entry_mode)" == "xray-fallback" && -n "${XRAY_LISTEN_ADDR:-}" && -n "${XRAY_LISTEN_PORT:-}" ]]; then
        for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            if [[ "$XRAY_LISTEN_ADDR" == "${XRAY_SNI_ROUTE_ADDRS[$i]}" && "$XRAY_LISTEN_PORT" == "${XRAY_SNI_ROUTE_PORTS[$i]}" ]]; then
                echo "$i"
                return 0
            fi
        done
    fi
    return 1
}

set_xray_fallback_main_route_from_index() {
    local idx="$1"
    [[ "$idx" =~ ^[0-9]+$ ]] || return 1
    (( idx >= 0 && idx < ${#XRAY_SNI_ROUTE_SNIS[@]} )) || return 1
    XRAY_FALLBACK_MAIN_SNI="${XRAY_SNI_ROUTE_SNIS[$idx]}"
    XRAY_FALLBACK_MAIN_ADDR="${XRAY_SNI_ROUTE_ADDRS[$idx]}"
    XRAY_FALLBACK_MAIN_PORT="${XRAY_SNI_ROUTE_PORTS[$idx]}"
}

print_xray_fallback_mode_explanation() {
    echo -e "$(localized_text "${YELLOW}Xray 本身可以有多个入站。但在 xray-fallback 模式下，公网 443 默认由一个 Xray 主入站接管。脚本暂不支持在该模式下继续按多个 SNI 分流到多个本地 Xray 入站。${PLAIN}" "${YELLOW}Xray itself can have multiple inbounds. But in xray-fallback mode, public port 443 is taken over by a Xray main inbound by default. The script currently does not support continuing to routing multiple SNI to multiple local Xray inbound in this mode.${PLAIN}" "${YELLOW}Xray сам по себе может иметь несколько входящих подключений. Но в резервном режиме xray публичный порт 443 по умолчанию перехватывается основным входящим подключением Xray. В настоящее время сценарий не поддерживает продолжение перенаправления нескольких SNI на несколько локальных входящих Xray в этом режиме.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}该模式只负责 Xray 主入站监听公网 443，并 fallback 普通 HTTPS 到所选 Web 反代引擎。${PLAIN}" "${YELLOW}This mode is only responsible for Xray's main inbound listening of public port 443, and fallback normal HTTPS to the selected Web reverse proxy engine.${PLAIN}" "${YELLOW}Этот режим отвечает только за основной входящий прослушивание Xray публичного порта 443 и возврат обычного HTTPS к выбранному механизму веб-прокси.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如需多个本地 Xray 入站通过 443 按 SNI 分流，请使用 Nginx Stream 模式或 TCP Peek + Splice 模式。${PLAIN}" "${YELLOW}If you need multiple local Xray inbound pass 443 split by SNI, please use Nginx Stream mode or TCP Peek + Splice mode.${PLAIN}" "${YELLOW}Если вам нужно несколько локальных входящих проходов Xray 443, разделенных на SNI, используйте режим Nginx Stream или режим TCP Peek + Splice.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如果 Web 域名开启 CDN/WAF/源站保护/Cloudflare 回源限制/Caddy 白名单，403 或拒绝访问通常是 Web/CDN/白名单/SNI 策略阻断，不一定是证书或 Caddy 故障。${PLAIN}" "${YELLOW}If the Web domain has CDN/WAF/origin protection/Cloudflare return-to-origin restriction/Caddy whitelist enabled, 403 or access denied is usually blocked by the Web/CDN/whitelist/SNI policy, and is not necessarily a certificate or Caddy fault.${PLAIN}" "${YELLOW}Если имя веб-домена имеет CDN/WAF/защиту происхождения/ограничение возврата к источнику Cloudflare/белый список Caddy, ошибка 403 или отказ в доступе обычно блокируется политикой Web/CDN/белый список/SNI и не обязательно является сертификатом или ошибкой Caddy.${PLAIN}")"
}

print_xray_fallback_main_route_summary() {
    local idx
    idx=$(xray_fallback_main_route_index 2>/dev/null || true)
    if [[ -n "$idx" ]]; then
        echo -e "$(localized_text "${GREEN}当前 xray-fallback 主入站：${XRAY_SNI_ROUTE_SNIS[$idx]} -> ${XRAY_SNI_ROUTE_ADDRS[$idx]}:${XRAY_SNI_ROUTE_PORTS[$idx]}${PLAIN}" "${GREEN}Current xray-fallback main inbound: ${XRAY_SNI_ROUTE_SNIS[$idx]} -> ${XRAY_SNI_ROUTE_ADDRS[$idx]}:${XRAY_SNI_ROUTE_PORTS[$idx]}${PLAIN}" "${GREEN}текущий xray-резервный основной входящий: ${XRAY_SNI_ROUTE_SNIS[$idx]} -> ${XRAY_SNI_ROUTE_ADDRS[$idx]}:${XRAY_SNI_ROUTE_PORTS[$idx]}${PLAIN}")"
    elif [[ -n "${XRAY_FALLBACK_MAIN_SNI:-}" ]]; then
        echo -e "$(localized_text "${YELLOW}当前 xray-fallback 主入站记录：${XRAY_FALLBACK_MAIN_SNI} -> ${XRAY_FALLBACK_MAIN_ADDR:-?}:${XRAY_FALLBACK_MAIN_PORT:-?}，但未匹配到现有规则。${PLAIN}" "${YELLOW}Current xray-fallback main inbound record: ${XRAY_FALLBACK_MAIN_SNI} -> ${XRAY_FALLBACK_MAIN_ADDR:-?}:${XRAY_FALLBACK_MAIN_PORT:-?}, but no existing rules are matched.${PLAIN}" "${YELLOW}Текущая основная входящая резервная запись xray: ${XRAY_FALLBACK_MAIN_SNI} -> ${XRAY_FALLBACK_MAIN_ADDR:-?}:${XRAY_FALLBACK_MAIN_PORT:-?}, но ни одно существующее правило не соответствует.${PLAIN}")"
    elif [[ "$(get_entry_mode)" == "xray-fallback" ]]; then
        echo -e "$(localized_text "${YELLOW}当前未记录 xray-fallback 主入站；请确认 Xray 主入站已按当前模式监听公网 443。${PLAIN}" "${YELLOW}Is currently not recorded. xray-fallback main inbound; please confirm that Xray main inbound is listening on the public in the current mode 443.${PLAIN}" "${YELLOW}в настоящее время не записан. xray-резервный основной входящий; пожалуйста, подтвердите, что основное входящее подключение Xray прослушивает публичную сеть в текущем режиме 443.${PLAIN}")"
    fi
}

select_xray_fallback_main_route_for_switch() {
    load_sni_stack_env || return 1
    local count choice idx
    count=${#XRAY_SNI_ROUTE_SNIS[@]}

    if [[ "$count" -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}未找到 $(xray_sni_routes_path) 中的 Xray 入站分流规则。${PLAIN}" "${YELLOW}Did not find the Xray inbound routing rule in $(xray_sni_routes_path).${PLAIN}" "${YELLOW}Правило маршрутизации входящего подключения Xray не найдено в $(xray_sni_routes_path).${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}切换到 xray-fallback 时，将由用户已配置的 Xray 主入站接管公网 443；脚本不会修改 3x-ui/Xray 入站内部配置。${PLAIN}" "${YELLOW}When switching to xray-fallback, the Xray main inbound configured by the user will take over the public port 443; the script will not modify the 3x-ui/Xray inbound internal configuration.${PLAIN}" "${YELLOW}Когда  переключается на резервный xray, публичный порт 443 будет занят настраиваемым пользователем основным входящим соединением Xray; сценарий не будет изменять внутреннюю конфигурацию входящего соединения 3x-ui/Xray.${PLAIN}")"
        confirm_risk_action "$(localized_text "继续切换到 xray-fallback" "Continue to switch to xray-fallback" "Продолжить переход на резервный вариант xray.")" \
            "$(localized_text "公网 443 将由 Xray 主入站接管，普通 HTTPS fallback 到所选 Web 反代引擎" "public port 443 will be taken over by Xray main inbound, and ordinary HTTPS fallback to the selected web reverse proxy engine" "Публичная сеть 443 будет занята основным входящим подключением Xray и обычным резервным HTTPS для выбранного механизма веб-прокси.")" \
            "$(localized_text "取消切换，先在 Xray 入站管理中记录一个主入站候选" "To cancel the switch, first record a primary inbound candidate in Xray inbound management" "Чтобы отменить переключение, сначала запишите кандидата на роль основного входящего подключения в системе управления входящими подключениями Xray.")" \
            "$(localized_text "确认你已经在 3x-ui/Xray 中准备好将作为主入站的配置。" "Confirm that you have prepared the configuration in 3x-ui/Xray that will serve as the primary inbound." "Подтвердите, что вы подготовили конфигурацию в 3x-ui/Xray, которая будет служить основным входящим подключением.")" || return 1
        XRAY_FALLBACK_MAIN_SNI=""
        XRAY_FALLBACK_MAIN_ADDR=""
        XRAY_FALLBACK_MAIN_PORT=""
        return 0
    fi

    print_xray_fallback_mode_explanation
    echo -e "------------------------------------------------"
    if [[ "$count" -eq 1 ]]; then
        echo -e "$(localized_text "${CYAN}检测到 1 条 Xray 入站分流规则，可作为 xray-fallback 主入站候选：${PLAIN}" "${CYAN}Detects 1 Xray inbound routing rule, which can be used as the xray-fallback main inbound candidate:${PLAIN}" "${CYAN}Обнаружено одно правило маршрутизации входящего подключения Xray, которое можно использовать в качестве основного входящего кандидата для xray:${PLAIN}")"
        echo -e "1. ${XRAY_SNI_ROUTE_SNIS[0]} -> ${XRAY_SNI_ROUTE_ADDRS[0]}:${XRAY_SNI_ROUTE_PORTS[0]}"
        confirm_risk_action "$(localized_text "使用该规则作为 xray-fallback 主入站候选" "Use this rule as the xray-fallback primary inbound candidate" "Используйте это правило в качестве резервного основного входящего кандидата xray.")" \
            "$(localized_text "该规则会被记录为 xray-fallback 主入站；其他模式下仍按 xray-sni-routes.conf 正常分流" "This rule will be recorded as xray-fallback main inbound; in other modes, it will still be distributed normally according to xray-sni-routes.conf" "Это правило будет записано как основной входящий xray-резервный; в остальных режимах всё равно будет нормально раздаваться согласно xray-sni-routes.conf")" \
            "$(localized_text "取消切换，先确认 3x-ui/Xray 主入站配置" "To cancel the switch, first confirm the 3x-ui/Xray main inbound configuration" "Чтобы отменить переключение, сначала подтвердите основную входящую конфигурацию 3x-ui/Xray.")" \
            "$(localized_text "确认该本地入站就是你希望在 xray-fallback 模式下接管公网 443 的主入站。" "Confirm that this local inbound is the primary inbound that you want to take over public port 443 in xray-fallback mode." "Подтвердите, что это локальное входящее подключение является основным входящим подключением, который вы хотите использовать для публичного порта 443 в резервном режиме xray.")" || return 1
        set_xray_fallback_main_route_from_index 0
        return 0
    fi

    echo -e "$(localized_text "${CYAN}检测到多条 Xray 入站分流规则，请选择其中一条作为 xray-fallback 主入站：${PLAIN}" "${CYAN}Detects multiple Xray inbound routing rules, please select one of them as the xray-fallback main inbound:${PLAIN}" "${CYAN}обнаруживает несколько правил маршрутизация входящего подключения Xray. Выберите одно из них в качестве резервного основного входящего подключения xray:.${PLAIN}")"
    for idx in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        echo -e "${GREEN}$((idx + 1)).${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$idx]} -> ${XRAY_SNI_ROUTE_ADDRS[$idx]}:${XRAY_SNI_ROUTE_PORTS[$idx]}"
    done
    echo -e "$(localized_text "${RED}0. 取消切换${PLAIN}" "${RED}0. Cancel switching${PLAIN}" "${RED}0. Отменить переключение${PLAIN}")"
    read_trimmed choice "$(localized_text "请选择 xray-fallback 主入站候选: " "Please select xray-fallback primary inbound candidate:" "Пожалуйста, выберите xray-резервный основной входящий кандидат:")"
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消切换到 xray-fallback。${PLAIN}" "${BLUE}Canceled the switch to xray-fallback.${PLAIN}" "${BLUE}отменил переход на резервный вариант xray.${PLAIN}")"
        return 1
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > count )); then
        echo -e "$(localized_text "${RED}❌ 序号无效，已取消切换。${PLAIN}" "${RED}❌ The serial number is invalid and the switching has been cancelled.${PLAIN}" "${RED}❌ Серийный номер недействителен, переключение отменено.${PLAIN}")"
        return 1
    fi
    set_xray_fallback_main_route_from_index "$((choice - 1))" || return 1
    echo -e "$(localized_text "${GREEN}✅ 已选择 xray-fallback 主入站候选：${XRAY_FALLBACK_MAIN_SNI} -> ${XRAY_FALLBACK_MAIN_ADDR}:${XRAY_FALLBACK_MAIN_PORT}${PLAIN}" "${GREEN}✅ xray-fallback main inbound candidate selected: ${XRAY_FALLBACK_MAIN_SNI} -> ${XRAY_FALLBACK_MAIN_ADDR}:${XRAY_FALLBACK_MAIN_PORT}${PLAIN}" "${GREEN}✅ xray — выбран резервный основной входящий кандидат: ${XRAY_FALLBACK_MAIN_SNI} -> ${XRAY_FALLBACK_MAIN_ADDR}:${XRAY_FALLBACK_MAIN_PORT}${PLAIN}")"
}

xray_sni_route_port_conflict() {
    local addr="$1"
    local port="$2"
    local skip_idx="${3:-}"
    local i
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ -n "$skip_idx" && "$i" == "$skip_idx" ]] && continue
        if [[ "$addr" == "${XRAY_SNI_ROUTE_ADDRS[$i]}" && "$port" == "${XRAY_SNI_ROUTE_PORTS[$i]}" ]]; then
            echo "${XRAY_SNI_ROUTE_SNIS[$i]}"
            return 0
        fi
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        if [[ "$addr" == "${TCP_ROUTE_ADDRS[$i]}" && "$port" == "${TCP_ROUTE_PORTS[$i]}" ]]; then
            echo "$(localized_text "旧 TCP/SNI:${TCP_ROUTE_SNIS[$i]}" "Old TCP/SNI:${TCP_ROUTE_SNIS[$i]}" "Старый TCP/SNI:${TCP_ROUTE_SNIS[$i]}")"
            return 0
        fi
    done
    return 1
}

xray_route_listen_line_by_addr_port() {
    local addr="$1"
    local port="$2"
    local host_regex
    case "$addr" in
        "127.0.0.1") host_regex='(127\.0\.0\.1|0\.0\.0\.0|\*)' ;;
        "::1") host_regex='(\[::1\]|\[::\]|\*)' ;;
        "localhost") host_regex='(127\.0\.0\.1|0\.0\.0\.0|\[::1\]|\[::\]|\*)' ;;
        *) host_regex=$(printf '%s' "$addr" | sed 's/[.[\*^$()+?{}|\\]/\\&/g') ;;
    esac
    ss -lntp 2>/dev/null | grep -E "${host_regex}:${port}[[:space:]]" | head -n1 || true
}

print_xray_route_port_status() {
    local sni="$1"
    local addr="$2"
    local port="$3"
    local line conflict

    echo -e "${CYAN}${sni}${PLAIN} -> ${addr}:${port}"
    if [[ "${CADDY_LISTEN_PORT:-}" == "$port" ]]; then
        echo -e "$(localized_text "${RED}  ❌ 与 Web 反代引擎本地端口 ${CADDY_LISTEN_PORT} 冲突，请换一个本地入站端口。${PLAIN}" "${RED}❌ Conflicts with the local port ${CADDY_LISTEN_PORT} of the Web reverse proxy engine. Please change the local inbound port.${PLAIN}" "${RED}❌ Конфликты с локальным портом ${CADDY_LISTEN_PORT} механизма веб-прокси. Пожалуйста, измените локальный входящий порт.${PLAIN}")"
    fi

    conflict=$(xray_sni_route_port_conflict "$addr" "$port" "$(xray_sni_route_index "$sni" 2>/dev/null || true)" || true)
    [[ -n "$conflict" ]] && echo -e "$(localized_text "${YELLOW}  ⚠️ 与规则 ${conflict} 使用了相同的 ${addr}:${port}，请确认是否故意复用。${PLAIN}" "${YELLOW}⚠️ Uses the same ${addr}:${port} as rule ${conflict}. Please confirm whether it is reused intentionally.${PLAIN}" "${YELLOW}⚠️ Использует тот же ${addr}:${port}, что и правило ${conflict}. Пожалуйста, подтвердите, намеренно ли он используется повторно.${PLAIN}")"

    line=$(xray_route_listen_line_by_addr_port "$addr" "$port")
    if [[ -n "$line" ]]; then
        echo -e "$(localized_text "${GREEN}  ✅ 端口已监听：${line}${PLAIN}" "${GREEN}✅ Port is listening: ${line}${PLAIN}" "${GREEN}✅ Порт прослушивается: ${line}${PLAIN}")"
        if echo "$line" | grep -Eq '(^|[[:space:]])(0\.0\.0\.0|\*|\[::\]):'"${port}"'[[:space:]]'; then
            echo -e "$(localized_text "${YELLOW}  ⚠️ 检测到可能监听在 0.0.0.0/[::]，存在公网暴露风险，建议改为 127.0.0.1。${PLAIN}" "${YELLOW}⚠️ Detected that it may be monitored at 0.0.0.0/[::], which is a risk of Internet exposure. It is recommended to change it to 127.0.0.1.${PLAIN}" "${YELLOW}⚠️ Обнаружено, что его можно отслеживать по адресу 0.0.0.0/[::]. Существует риск публичного доступа. Рекомендуется изменить его на 127.0.0.1.${PLAIN}")"
        fi
    else
        echo -e "$(localized_text "${YELLOW}  ⚠️ 未检测到 ${addr}:${port} 监听，请先去 3x-ui 创建并启用对应入站。${PLAIN}" "${YELLOW}⚠️ The ${addr}:${port} monitor is not detected. Please go to 3x-ui first to create and enable the corresponding inbound connection.${PLAIN}" "${YELLOW}⚠️ Монитор ${addr}:${port} не обнаружен. Сначала перейдите по адресу 3x-ui, чтобы создать и включить соответствующее входящее соединение.${PLAIN}")"
    fi
}
