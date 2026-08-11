# shellcheck shell=bash
# Port 443 Reuse shared environment, route, listener, and whitelist helpers.

detect_vps_public_ip_by_family() {
    local family="$1"
    local curl_flag="-4"
    local endpoint ip
    local endpoints=()

    command -v curl >/dev/null 2>&1 || return 1

    if [[ "$family" == "6" ]]; then
        curl_flag="-6"
        endpoints=("https://api6.ipify.org" "https://ipv6.icanhazip.com")
    else
        endpoints=("https://api.ipify.org" "https://ipv4.icanhazip.com")
    fi

    for endpoint in "${endpoints[@]}"; do
        ip=$(curl "$curl_flag" -fsS --connect-timeout 3 --max-time 5 "$endpoint" 2>/dev/null | tr -d '\r' | awk 'NF {print $1; exit}')
        ip=$(trim_input "$ip")
        if [[ "$family" == "6" ]]; then
            is_valid_ipv6_cidr "$ip" && { echo "$ip"; return 0; }
        else
            is_valid_ipv4_cidr "$ip" && ! is_suspicious_public_ipv4 "$ip" && { echo "$ip"; return 0; }
        fi
    done
    return 1
}

append_vps_public_ips_to_whitelist() {
    local -n out_array=$1
    local ip existing seen added=0
    seen=" "
    for existing in "${out_array[@]}"; do
        seen+=" ${existing} "
    done

    for ip in "$(detect_vps_public_ip_by_family 4 2>/dev/null)" "$(detect_vps_public_ip_by_family 6 2>/dev/null)"; do
        [[ -n "$ip" ]] || continue
        if [[ "$seen" != *" ${ip} "* ]]; then
            out_array+=("$ip")
            seen+=" ${ip} "
            echo -e "$(localized_text "${GREEN}✅ 已自动加入 VPS 本机公网 IP：${ip}${PLAIN}" "${GREEN}✅ has automatically joined the VPS. Local public IP: ${ip}${PLAIN}" "${GREEN}✅ автоматически присоединился к VPS. IP-адрес локальной публичной сети: ${ip}.${PLAIN}")"
            added=1
        fi
    done

    if [[ "$added" -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未能自动获取 VPS 本机公网 IP；如需要本机自测访问，请手动加入 VPS 公网 IP。${PLAIN}" "${YELLOW}⚠️ Failed to automatically obtain the VPS local public IP; if you need local self-test access, please manually add the VPS public IP.${PLAIN}" "${YELLOW}⚠️ Не удалось автоматически получить IP-адрес локальной публичной сети VPS; Если вам нужен локальный доступ для самотестирования, вручную добавьте IP-адрес публичной сети VPS.${PLAIN}")"
    fi

    append_local_service_ips_to_whitelist "$1" seen
}

append_local_service_ips_to_whitelist() {
    local -n out_array=$1
    local -n seen_ref=$2
    local entry subnet local_added=0
    local -a local_ranges=("127.0.0.1/32" "::1/128")

    if command -v docker >/dev/null 2>&1; then
        while IFS= read -r subnet; do
            subnet=$(trim_input "$subnet")
            [[ -n "$subnet" ]] && local_ranges+=("$subnet")
        done < <(docker network inspect $(docker network ls -q 2>/dev/null) \
            --format '{{range .IPAM.Config}}{{if .Subnet}}{{.Subnet}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | sort -u)
    fi

    for entry in "${local_ranges[@]}"; do
        [[ -n "$entry" ]] || continue
        is_valid_ip_cidr "$entry" || continue
        if [[ "$seen_ref" != *" ${entry} "* ]]; then
            out_array+=("$entry")
            seen_ref+=" ${entry} "
            echo -e "$(localized_text "${GREEN}✅ 已自动加入本机/容器访问来源：${entry}${PLAIN}" "${GREEN}✅ has been automatically added to this machine/container. Access source: ${entry}${PLAIN}" "${GREEN}вещество было автоматически добавлено в эту машину/контейнер. Источник доступа: ${entry}${PLAIN}")"
            local_added=1
        fi
    done

    if [[ "$local_added" -eq 0 ]]; then
        echo -e "$(localized_text "${BLUE}ℹ️ 本机/容器访问来源已在白名单中，无需重复加入。${PLAIN}" "${BLUE}ℹ️ The local/container access source is already in the whitelist and there is no need to add it again.${PLAIN}" "${BLUE}ℹ️ Локальный/контейнерный источник доступа уже находится в белом списке, и нет необходимости добавлять его снова.${PLAIN}")"
    fi
}

join_array_by_space() {
    local IFS=' '
    echo "$*"
}

detect_ssh_client_ip() {
    local client_ip=""
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        client_ip="${SSH_CONNECTION%% *}"
    elif [[ -n "${SSH_CLIENT:-}" ]]; then
        client_ip="${SSH_CLIENT%% *}"
    fi
    echo "$client_ip"
}

caddy_ip_whitelist_block() {
    local ranges="$1"
    [[ -z "$ranges" ]] && return 0
    cat <<EOF
    # vps-optimize-ip-whitelist-start
    @vps_ip_denied not remote_ip ${ranges}
    abort @vps_ip_denied
    # vps-optimize-ip-whitelist-end

EOF
}

normalize_web_proxy_engine() {
    local engine="${1:-caddy}"
    engine=$(echo "$engine" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    case "$engine" in
        ""|"caddy") echo "caddy" ;;
        "nginx"|"nginx-local"|"nginx-http") echo "nginx" ;;
        *) return 1 ;;
    esac
}

current_web_proxy_engine() {
    WEB_PROXY_ENGINE=$(normalize_web_proxy_engine "${WEB_PROXY_ENGINE:-caddy}" 2>/dev/null || echo "caddy")
    echo "$WEB_PROXY_ENGINE"
}

web_proxy_engine_label() {
    case "$(normalize_web_proxy_engine "${1:-${WEB_PROXY_ENGINE:-caddy}}" 2>/dev/null || echo caddy)" in
        nginx) echo "$(localized_text "Nginx 本地 HTTPS 反代" "Nginx local HTTPS reverse proxy" "Nginx локальная HTTPS обратный прокси")" ;;
        *) echo "$(localized_text "Caddy 本地 HTTPS 反代" "Caddy local HTTPS reverse proxy" "Caddy локальная HTTPS обратный прокси")" ;;
    esac
}

web_proxy_backend() {
    format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT"
}

web_proxy_engine_supports_web_whitelist() {
    local mode="${1:-${ENTRY_MODE:-$(get_entry_mode)}}"
    mode=$(normalize_entry_mode_name "$mode" 2>/dev/null || echo "nginx-stream")

    # Xray fallback reconnects to the local Web proxy, so neither Caddy remote_ip
    # nor Nginx allow/deny can reliably identify the original client address.
    [[ "$mode" == "xray-fallback" ]] && return 1
    return 0
}

assert_web_proxy_whitelist_supported() {
    local mode="${1:-${ENTRY_MODE:-$(get_entry_mode)}}"
    local engine="${2:-${WEB_PROXY_ENGINE:-caddy}}"
    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -eq 0 ]]; then
        return 0
    fi
    if web_proxy_engine_supports_web_whitelist "$mode" "$engine"; then
        return 0
    fi
    echo -e "$(localized_text "${RED}❌ xray-fallback 模式不支持 Web 白名单。${PLAIN}" "${RED}❌ xray-fallback mode does not support web whitelisting.${PLAIN}" "${RED}❌ Резервный режим xray не поддерживает белый список веб-сайтов.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}原因：Xray fallback 到本地 Web 反代引擎后，Caddy/Nginx 无法可靠拿到真实客户端源 IP。${PLAIN}" "${YELLOW}Reason: After Xray fallback to the local Web reverse proxy engine, Caddy/Nginx cannot reliably obtain the real client source IP.${PLAIN}" "${YELLOW}Причина: после перехода Xray к локальному механизму веб-прокси Caddy/Nginx не может надежно получить реальный исходный IP-адрес клиента.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}请改用 Nginx Stream/TCP Peek 入口模式，或先清除 Web 白名单后再使用该组合。${PLAIN}" "${YELLOW}Please use Nginx Stream/TCP Peek entry mode instead, or clear the Web whitelist before using this combination.${PLAIN}" "${YELLOW}Вместо этого используйте режим входа Nginx Stream/TCP Peek или очистите белый список Интернета перед использованием этой комбинации.${PLAIN}")"
    return 1
}

xui_setting_default_value() {
    local key="$1"
    case "$key" in
        webListen|subListen|webDomain|subDomain|webCertFile|webKeyFile|subCertFile|subKeyFile|subURI|subClashURI) echo "" ;;
        webPort) echo "2053" ;;
        webBasePath) echo "/" ;;
        subPort) echo "2096" ;;
        subPath) echo "/sub/" ;;
        subClashPath) echo "/clash/" ;;
        *) echo "" ;;
    esac
}

xui_backend_addr_from_listen() {
    local listen_addr
    listen_addr="$(trim_input "$1")"
    case "$listen_addr" in
        ""|"0.0.0.0"|"::") echo "127.0.0.1" ;;
        "localhost") echo "127.0.0.1" ;;
        *) echo "$listen_addr" ;;
    esac
}

detect_xui_command() {
    if [[ -x /usr/local/x-ui/x-ui ]]; then
        echo "/usr/local/x-ui/x-ui"
    elif command -v x-ui >/dev/null 2>&1; then
        command -v x-ui
    elif command -v 3x-ui >/dev/null 2>&1; then
        command -v 3x-ui
    fi
}

xui_database_backend() {
    local env_file raw value
    for env_file in /etc/default/x-ui /etc/sysconfig/x-ui /etc/conf.d/x-ui; do
        [[ -r "$env_file" ]] || continue
        raw=$(grep -E '^[[:space:]]*(export[[:space:]]+)?XUI_DB_TYPE[[:space:]]*=' "$env_file" | tail -n1 || true)
        [[ -n "$raw" ]] || continue
        value="${raw#*=}"
        value="${value%%#*}"
        value="$(trim_input "$value")"
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
        case "$value" in
            postgres|postgresql|pg)
                printf '%s' "postgresql"
                return 0
                ;;
        esac
    done
    printf '%s' "sqlite"
}

xui_uses_postgresql() {
    [[ "$(xui_database_backend)" == "postgresql" ]]
}

xui_postgresql_manual_notice() {
    echo -e "$(localized_text "${YELLOW}⚠️ 检测到 3x-ui 使用 PostgreSQL。VPS-Optimize 不会自动检查或修改 PostgreSQL；请在 3x-ui 中手动确认 webCertFile、webKeyFile、subCertFile、subKeyFile 已清空。${PLAIN}" "${YELLOW}⚠️ 3x-ui is configured to use PostgreSQL. VPS-Optimize does not inspect or modify PostgreSQL automatically; verify manually in 3x-ui that webCertFile, webKeyFile, subCertFile, and subKeyFile are empty.${PLAIN}" "${YELLOW}⚠️ Обнаружено, что 3x-ui использует PostgreSQL. VPS-Optimize не проверяет и не изменяет PostgreSQL автоматически; вручную убедитесь в 3x-ui, что webCertFile, webKeyFile, subCertFile и subKeyFile пусты.${PLAIN}")"
}

xui_cli_show_value() {
    local key="$1"
    local xui_bin info cli_key
    xui_bin=$(detect_xui_command) || return 1
    info=$("$xui_bin" setting -show true 2>/dev/null || true)
    [[ -n "$info" ]] || return 1
    case "$key" in
        webPort) cli_key="port" ;;
        webBasePath) cli_key="webBasePath" ;;
        *) cli_key="$key" ;;
    esac
    printf '%s\n' "$info" | awk -F': ' -v k="$cli_key" '$1 == k {print $2; exit}'
}

xui_db_setting_value() {
    local key="$1"
    local db_path value
    xui_uses_postgresql && return 1
    command -v sqlite3 >/dev/null 2>&1 || return 1
    while IFS= read -r db_path; do
        [[ -n "$db_path" && -f "$db_path" ]] || continue
        value=$(sqlite3 "$db_path" "select value from settings where lower(key)=lower('${key}') limit 1;" 2>/dev/null || true)
        if [[ -z "$value" ]]; then
            value=$(sqlite3 "$db_path" "select value from setting where lower(key)=lower('${key}') limit 1;" 2>/dev/null || true)
        fi
        value="$(trim_input "$value")"
        if [[ -n "$value" ]]; then
            printf '%s' "$value"
            return 0
        fi
    done < <(find_xui_database_candidates)
    return 1
}

xui_detect_setting_value() {
    local key="$1"
    local default_value="${2:-$(xui_setting_default_value "$key")}"
    local value
    value="$(xui_cli_show_value "$key" 2>/dev/null || true)"
    value="$(trim_input "$value")"
    if [[ -z "$value" ]]; then
        value="$(xui_db_setting_value "$key" 2>/dev/null || true)"
        value="$(trim_input "$value")"
    fi
    printf '%s' "${value:-$default_value}"
}

detect_xui_single_443_defaults() {
    XUI_DETECTED_BIN="$(detect_xui_command 2>/dev/null || true)"
    XUI_DETECTED_DB="$(find_xui_database_candidates | head -n1)"
    XUI_DETECTED_WEB_LISTEN="$(xui_detect_setting_value webListen)"
    XUI_DETECTED_WEB_PORT="$(xui_detect_setting_value webPort 2053)"
    XUI_DETECTED_WEB_BASE_PATH="$(normalize_path_prefix "$(xui_detect_setting_value webBasePath /)")"
    XUI_DETECTED_SUB_LISTEN="$(xui_detect_setting_value subListen)"
    XUI_DETECTED_SUB_PORT="$(xui_detect_setting_value subPort 2096)"
    XUI_DETECTED_SUB_PATH="$(normalize_path_prefix "$(xui_detect_setting_value subPath /sub/)")"
    XUI_DETECTED_SUB_CLASH_PATH="$(normalize_path_prefix "$(xui_detect_setting_value subClashPath /clash/)")"
    XUI_DETECTED_PANEL_ADDR="$(xui_backend_addr_from_listen "$XUI_DETECTED_WEB_LISTEN")"
    XUI_DETECTED_SUB_ADDR="$(xui_backend_addr_from_listen "$XUI_DETECTED_SUB_LISTEN")"
}

print_xui_single_443_detected_defaults() {
    if [[ -z "${XUI_DETECTED_BIN:-}" && -z "${XUI_DETECTED_DB:-}" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 3x-ui 命令或数据库，将使用 443 向导默认值。${PLAIN}" "${YELLOW}⚠️ No 3x-ui command or database detected, 443 wizard default will be used.${PLAIN}" "${YELLOW}⚠️ Команда или база данных 3x-ui не обнаружены, будет использоваться мастер 443 по умолчанию.${PLAIN}")"
        return 0
    fi
    echo -e "$(localized_text "${CYAN}▶ 已检测到 3x-ui 当前设置，下面会作为默认值，可按回车沿用：${PLAIN}" "${CYAN}▶ The current setting of 3x-ui has been detected. The following will be used as the default value. You can press Enter to use it:${PLAIN}" "${CYAN}▶ Обнаружена текущая настройка 3x-ui. Следующее значение будет использоваться в качестве значения по умолчанию. Вы можете нажать Enter, чтобы использовать его:.${PLAIN}")"
    [[ -n "${XUI_DETECTED_BIN:-}" ]] && echo -e "$(localized_text "  命令：${XUI_DETECTED_BIN}" "Command: ${XUI_DETECTED_BIN}" "Команда: ${XUI_DETECTED_BIN}")"
    [[ -n "${XUI_DETECTED_DB:-}" ]] && echo -e "$(localized_text "  数据库：${XUI_DETECTED_DB}" "Database: ${XUI_DETECTED_DB}" "База данных: ${XUI_DETECTED_DB}")"
    echo -e "$(localized_text "  面板后端：${XUI_DETECTED_PANEL_ADDR}:${XUI_DETECTED_WEB_PORT}${XUI_DETECTED_WEB_BASE_PATH}" "Panel backend: ${XUI_DETECTED_PANEL_ADDR}:${XUI_DETECTED_WEB_PORT}${XUI_DETECTED_WEB_BASE_PATH}" "бэкенд панели: ${XUI_DETECTED_PANEL_ADDR}:${XUI_DETECTED_WEB_PORT}${XUI_DETECTED_WEB_BASE_PATH}")"
    echo -e "$(localized_text "  订阅后端：${XUI_DETECTED_SUB_ADDR}:${XUI_DETECTED_SUB_PORT}${XUI_DETECTED_SUB_PATH}" "Subscription backend: ${XUI_DETECTED_SUB_ADDR}:${XUI_DETECTED_SUB_PORT}${XUI_DETECTED_SUB_PATH}" "бэкенд подписки: ${XUI_DETECTED_SUB_ADDR}:${XUI_DETECTED_SUB_PORT}${XUI_DETECTED_SUB_PATH}")"
    echo -e "$(localized_text "  Clash/Mihomo 路径：${XUI_DETECTED_SUB_CLASH_PATH}" "Clash/Mihomo Path: ${XUI_DETECTED_SUB_CLASH_PATH}" "Clash/Mihomo Путь: ${XUI_DETECTED_SUB_CLASH_PATH}")"
}

clear_xui_cert_settings_for_single_443() {
    local xui_bin cert_cmd_done=false db_found=false cert_key_sql db_path service_name
    if xui_uses_postgresql; then
        xui_postgresql_manual_notice
        return 1
    fi
    xui_bin=$(detect_xui_command 2>/dev/null || true)

    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "$(localized_text "${CYAN}▶ 正在安装 sqlite3，用于清空 3x-ui 数据库里的证书路径...${PLAIN}" "${CYAN}▶ Installing sqlite3, used to clear the certificate path in the 3x-ui database...${PLAIN}" "${CYAN}▶ Установка sqlite3, используемого для очистки пути сертификата в базе данных 3x-ui...${PLAIN}")"
        install_pkg sqlite3 sqlite >/dev/null 2>&1 || true
    fi

    for service_name in x-ui 3x-ui x-panel; do
        systemctl stop "$service_name" >/dev/null 2>&1 || true
    done

    if [[ -n "$xui_bin" ]]; then
        if "$xui_bin" cert -webCert "" -webCertKey "" >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ 已通过 3x-ui 官方 cert 命令清空面板证书路径。${PLAIN}" "${GREEN}✅ The panel certificate path has been cleared through the 3x-ui official cert command.${PLAIN}" "${GREEN}. Путь сертификата панели очищен с помощью официальной команды сертификата 3x-ui.${PLAIN}")"
            cert_cmd_done=true
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 官方 cert 命令未能清空，将继续尝试修正数据库。${PLAIN}" "${YELLOW}⚠️ The official cert command failed to clear and will continue to try to correct the database.${PLAIN}" "${YELLOW}⚠️ Официальной команде сертификата не удалось очистить базу данных, и она продолжит попытки исправить базу данных.${PLAIN}")"
        fi
    fi

    if command -v sqlite3 >/dev/null 2>&1; then
        cert_key_sql=$(xui_cert_setting_key_sql_list)
        while IFS= read -r db_path; do
            [[ -f "$db_path" ]] || continue
            if sqlite3 "$db_path" "update settings set value='' where lower(key) in (${cert_key_sql});" 2>/dev/null || \
               sqlite3 "$db_path" "update setting set value='' where lower(key) in (${cert_key_sql});" 2>/dev/null; then
                echo -e "$(localized_text "${GREEN}✅ 已清空证书字段：${db_path}${PLAIN}" "${GREEN}✅ Certificate fields cleared: ${db_path}${PLAIN}" "${GREEN}✅ Поля сертификата очищены: ${db_path}${PLAIN}")"
                db_found=true
            fi
        done < <(find_xui_database_candidates)
    fi

    for service_name in x-ui 3x-ui x-panel; do
        if systemctl list-unit-files "${service_name}.service" --no-legend 2>/dev/null | grep -q . || systemctl status "$service_name" >/dev/null 2>&1; then
            systemctl restart "$service_name" >/dev/null 2>&1 || systemctl start "$service_name" >/dev/null 2>&1 || true
        fi
    done

    if ! $cert_cmd_done && ! $db_found; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未找到可自动清空的 3x-ui 证书设置，请在面板里手动清空证书路径并重启。${PLAIN}" "${YELLOW}⚠️ The 3x-ui certificate setting that can be automatically cleared was not found. Please manually clear the certificate path in the panel and restart.${PLAIN}" "${YELLOW}⚠️ Параметр сертификата 3x-ui, который можно автоматически очистить, не найден. Пожалуйста, вручную очистите путь к сертификату на панели и перезапустите.${PLAIN}")"
        return 1
    fi
    echo -e "$(localized_text "${GREEN}✅ 已尝试清空 3x-ui 面板/订阅证书路径，443端口复用将由 Web 反代引擎托管证书。${PLAIN}" "${GREEN}✅ Tried clearing the 3x-ui panel/subscription certificate path, 443 the Port 443 Reuse will have the certificate hosted by the web reverse proxy engine.${PLAIN}" "${GREEN}. Попробовал очистить путь сертификата панели/подписки 3x-ui, повторное использование порта 443 будет иметь сертификат, размещенный в механизме обратного веб-прокси.${PLAIN}")"
}













find_xui_database_candidates() {
    local db_path extra_db
    local seen_dbs=" "
    local db_candidates=(
        "/etc/x-ui/x-ui.db"
        "/usr/local/x-ui/x-ui.db"
        "/usr/local/x-ui/bin/x-ui.db"
        "/etc/x-panel/x-panel.db"
    )

    for db_path in "${db_candidates[@]}"; do
        [[ -f "$db_path" ]] || continue
        [[ "$seen_dbs" == *" ${db_path} "* ]] && continue
        seen_dbs+=" ${db_path} "
        echo "$db_path"
    done

    while IFS= read -r extra_db; do
        [[ -f "$extra_db" ]] || continue
        [[ "$seen_dbs" == *" ${extra_db} "* ]] && continue
        seen_dbs+=" ${extra_db} "
        echo "$extra_db"
    done < <(find /etc /usr/local/x-ui /opt -maxdepth 4 -type f \( -name "x-ui.db" -o -name "x-panel.db" \) 2>/dev/null | sort -u)
}

check_xui_cert_settings_for_single_443() {
    local cert_key_sql db_path rows key value
    local checked=0 found=0

    if xui_uses_postgresql; then
        xui_postgresql_manual_notice
        return 2
    fi

    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 sqlite3，跳过 3x-ui 证书路径数据库检查。${PLAIN}" "${YELLOW}⚠️ sqlite3 not detected, skipping 3x-ui certificate path database check.${PLAIN}" "${YELLOW}⚠️ sqlite3 не обнаружен, проверка базы данных пути сертификата 3x-ui пропускается.${PLAIN}")"
        return 2
    fi

    cert_key_sql=$(xui_cert_setting_key_sql_list)
    while IFS= read -r db_path; do
        [[ -n "$db_path" ]] || continue
        checked=1
        rows=$(sqlite3 -separator '|' "$db_path" "select key,value from settings where lower(key) in (${cert_key_sql}) and length(trim(coalesce(value,''))) > 0;" 2>/dev/null || true)
        [[ -n "$rows" ]] || continue

        found=1
        echo -e "$(localized_text "${YELLOW}⚠️ ${db_path} 仍有 3x-ui 面板/订阅证书路径。3.x 新安装应选择 Skip SSL；2.x/旧配置在 443端口复用下建议清空：${PLAIN}" "${YELLOW}⚠️ ${db_path} still has the 3x-ui panel/subscription certificate path. 3.x new installation should select Skip SSL; 2.x/old configuration is recommended to clear under the Port 443 Reuse:${PLAIN}" "${YELLOW}⚠️ ${db_path} по-прежнему имеет путь сертификата панели/подписки 3x-ui. 3.x при новой установке следует выбрать Пропустить SSL; Конфигурацию 2.x/old рекомендуется очистить под общей записью 443: .${PLAIN}")"
        while IFS='|' read -r key value; do
            [[ -n "$key" ]] || continue
            echo -e "  ${key}=${value}"
        done <<< "$rows"
    done < <(find_xui_database_candidates)

    if [[ "$checked" -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未找到 3x-ui 数据库，跳过证书路径检查。${PLAIN}" "${YELLOW}⚠️ 3x-ui database not found, skipping certificate path check.${PLAIN}" "${YELLOW}⚠️ База данных 3x-ui не найдена, проверка пути сертификата пропущена.${PLAIN}")"
        return 2
    fi

    if [[ "$found" -eq 1 ]]; then
        echo -e "$(localized_text "${YELLOW}建议：3.x 新安装回到安装器选择 Skip SSL / 不申请 SSL；2.x/旧配置进入 [5 面板、节点与订阅工具] -> [3 面板 SSL 修复]，或在 3x-ui 面板里清空证书路径并重启。${PLAIN}" "${YELLOW}Recommendation: For 3.x new installation, return to the installer and select Skip SSL / do not apply for SSL; for 2.x / old configuration, enter [5 Panel, Node and Subscription Tool] -> [3 Panel SSL Repair], or clear the certificate path in the 3x-ui panel and restart.${PLAIN}" "${YELLOW}Рекомендация: Для новой установки 3.x вернитесь к установщику и выберите «Пропустить SSL / не применять для SSL»; для конфигурации 2.x/старой введите [5 Panel, Node and Subscription Tool] -> [3 Panel SSL Repair] или очистите путь к сертификату на панели 3x-ui и перезапустите.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "${GREEN}✅ 3x-ui 面板/订阅证书路径未发现残留${PLAIN}" "${GREEN}✅ 3x-ui Panel/subscription certificate path No residual found${PLAIN}" "${GREEN}✅ 3x-ui Путь сертификата панели/подписки Остатки не найдены${PLAIN}")"
    return 0
}





cleanup_old_nginx_sni_stream_configs() {
    mkdir -p /etc/nginx/stream.d
    local old_dir="/etc/nginx/stream.d/backup_vps_sni_$(date +%Y%m%d_%H%M%S)"
    local moved=0
    while IFS= read -r conf_file; do
        mkdir -p "$old_dir"
        mv "$conf_file" "$old_dir/" >/dev/null 2>&1 && ((moved++))
    done < <(find /etc/nginx/stream.d -maxdepth 1 -type f -name 'vps_sni_*.conf' 2>/dev/null | sort)
    if [[ "$moved" -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 已隔离 ${moved} 个旧 Nginx SNI 配置到：${old_dir}${PLAIN}" "${YELLOW}⚠️ Isolated ${moved} old Nginx SNI configured to: ${old_dir}${PLAIN}" "${YELLOW}⚠️ Изолированный ${moved} старый Nginx SNI настроен на: ${old_dir}${PLAIN}")"
    fi
}

probe_reality_sni() {
    local sni="$1"
    echo -e "$(localized_text "${CYAN}▶ 正在检测 REALITY 伪装 SNI 连通性：${sni}:443${PLAIN}" "${CYAN}▶ Detecting REALITY Disguise SNI Connectivity: ${sni}:443${PLAIN}" "${CYAN}▶ Обнаружение REALITY Маскировка SNI Связь: ${sni}:443${PLAIN}")"
    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 openssl，跳过 SNI 连通性检测。${PLAIN}" "${YELLOW}⚠️ openssl not detected, skipping SNI connectivity detection.${PLAIN}" "${YELLOW}⚠️ openssl не обнаружен, пропускается обнаружение подключения SNI.${PLAIN}")"
        return 0
    fi
    if timeout 12 openssl s_client -connect "${sni}:443" -servername "$sni" </dev/null 2>/tmp/vps_reality_sni_probe.log | grep -q "BEGIN CERTIFICATE"; then
        echo -e "$(localized_text "${GREEN}✅ REALITY SNI 可连通并返回证书。${PLAIN}" "${GREEN}✅ REALITY SNI can connect and return the certificate.${PLAIN}" "${GREEN}✅ REALITY SNI может подключиться и вернуть сертификат.${PLAIN}")"
        return 0
    fi
    echo -e "$(localized_text "${RED}❌ REALITY SNI 检测失败：${sni}:443 未正常返回证书。${PLAIN}" "${RED}❌ REALITY SNI Detection failed: ${sni}:443 The certificate was not returned normally.${PLAIN}" "${RED}❌ REALITY SNI Ошибка обнаружения: ${sni}:443 Сертификат не был возвращен обычным образом.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}请更换一个外部真实 HTTPS 站点域名，不要使用模板域名或自己的面板域名。${PLAIN}" "${YELLOW}Please replace it with an external real HTTPS site domain. Do not use a template domain or your own panel domain.${PLAIN}" "${YELLOW}Пожалуйста, замените его внешним реальным доменным именем сайта HTTPS. Не используйте доменное имя шаблона или собственное доменное имя панели.${PLAIN}")"
    return 1
}

print_sni_stack_preview() {
    local entry_mode entry_label web_engine web_label web_backend
    entry_mode="${ENTRY_MODE:-nginx-stream}"
    entry_mode=$(normalize_entry_mode_name "$entry_mode" 2>/dev/null || echo "nginx-stream")
    web_engine=$(current_web_proxy_engine)
    web_label=$(web_proxy_engine_label "$web_engine")
    web_backend=$(web_proxy_backend)
    case "$entry_mode" in
        "nginx-stream") entry_label="$(localized_text "Nginx Stream 模式" "Nginx Stream mode" "Режим Nginx Stream")" ;;
        "xray-fallback") entry_label="$(localized_text "Xray Fallback 模式" "Xray Fallback mode" "Xray Резервный режим")" ;;
        "tcp-peek") entry_label="$(localized_text "TCP Peek + Splice 模式 / vpso-mux 分流器" "TCP Peek + Splice mode / vpso-mux routing" "Режим TCP Peek + Splice / маршрутизация vpso-mux")" ;;
        *) entry_label="$entry_mode" ;;
    esac

    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}即将写入的 443端口复用配置预览${PLAIN}" "${BOLD}Preview of Port 443 Reuse route configuration to be written${PLAIN}" "${BOLD}Предварительный просмотр конфигурации маршрутизации повторного использования порта 443, которая будет записана${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "配置模式 ENTRY_MODE：${entry_mode}" "Configuration mode ENTRY_MODE: ${entry_mode}" "Режим конфигурации ENTRY_MODE: ${entry_mode}")"
    echo -e "$(localized_text "Web 反代引擎 WEB_PROXY_ENGINE：${web_engine} (${web_label})" "Web reverse proxy engine WEB_PROXY_ENGINE: ${web_engine} (${web_label})" "механизм веб-прокси WEB_PROXY_ENGINE: ${web_engine} (${web_label})")"
    echo -e "$(localized_text "公网入口：${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${entry_label}" "public entry: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${entry_label}" "Вход в публичную сеть: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${entry_label}.")"
    echo -e "$(localized_text "面板域名：${PANEL_DOMAIN} -> ${web_backend} -> http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Panel domain: ${PANEL_DOMAIN} -> ${web_backend} -> http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Доменное имя панели: ${PANEL_DOMAIN} -> ${web_backend} -> http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}")"
    echo -e "$(localized_text "面板路径：https://${PANEL_DOMAIN}${PANEL_WEB_PATH:-/panel/}" "Panel path: https://${PANEL_DOMAIN}${PANEL_WEB_PATH:-/panel/}" "Путь панели: https://${PANEL_DOMAIN}${PANEL_WEB_PATH:-/panel/}")"
    echo -e "$(localized_text "普通订阅路径：https://${PANEL_DOMAIN}${SUB_URI_PATH:-/sub/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Ordinary subscription path: https://${PANEL_DOMAIN}${SUB_URI_PATH:-/sub/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Обычный путь подписки: https://${PANEL_DOMAIN}${SUB_URI_PATH:-/sub/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}.")"
    echo -e "$(localized_text "Clash/Mihomo 路径：https://${PANEL_DOMAIN}${CLASH_URI_PATH:-/clash/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Clash/Mihomo Path: https://${PANEL_DOMAIN}${CLASH_URI_PATH:-/clash/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Clash/Mihomo Путь: https://${PANEL_DOMAIN}${CLASH_URI_PATH:-/clash/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}")"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            echo -e "$(localized_text "网站/反代域名：${SITE_DOMAINS[$i]} -> ${web_backend} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}" "Website/reverse domain: ${SITE_DOMAINS[$i]} -> ${web_backend} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}" "Веб-сайт/обратное доменное имя: ${SITE_DOMAINS[$i]} -> ${web_backend} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}")"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "TCP/SNI 入站：${TCP_ROUTE_SNIS[$tcp_i]} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}" "TCP/SNI Inbound: ${TCP_ROUTE_SNIS[$tcp_i]} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}" "TCP/SNI Входящий: ${TCP_ROUTE_SNIS[$tcp_i]} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}")"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "Xray 入站分流：${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "Xray Inbound offload: ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "Xray Входящая разгрузка: ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}")"
        done
    fi
    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}域名 IP 白名单：${PLAIN}" "${YELLOW}Domain IP whitelist:${PLAIN}" "${YELLOW}Белый список IP-адресов доменного имени :${PLAIN}")"
        local wl_i
        for wl_i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
            echo -e "$(localized_text "  ${SNI_IP_WHITELIST_DOMAINS[$wl_i]} 仅允许 ${SNI_IP_WHITELIST_RANGES[$wl_i]}" "${SNI_IP_WHITELIST_DOMAINS[$wl_i]} Only ${SNI_IP_WHITELIST_RANGES[$wl_i]} is allowed" "${SNI_IP_WHITELIST_DOMAINS[$wl_i]} Разрешен только ${SNI_IP_WHITELIST_RANGES[$wl_i]}.")"
        done
    fi
    if [[ "$entry_mode" == "xray-fallback" ]]; then
        echo -e "$(localized_text "Xray 主入站：公网 ${NGINX_LISTEN_PORT} 由 Xray 接管，普通 HTTPS fallback 到 ${web_backend}" "Xray main inbound: public ${NGINX_LISTEN_PORT} is taken over by Xray, ordinary HTTPS fallsback to ${web_backend}" "Основной входящий Xray: публичную сеть ${NGINX_LISTEN_PORT} переходит под управление Xray, обычный HTTPS возвращается к ${web_backend}.")"
        echo -e "$(localized_text "提示：脚本不会创建或修改 3x-ui/Xray 入站内部配置。" "Tip: The script does not create or modify the 3x-ui/Xray inbound internal configuration." "Совет: Скрипт не создает и не изменяет входящую внутреннюю конфигурацию 3x-ui/Xray.")"
    else
        echo -e "REALITY SNI：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
        echo -e "$(localized_text "默认/未知 SNI -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}" "Default/Unknown SNI -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}" "По умолчанию/Неизвестно SNI -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}")"
    fi
    echo -e ""
    echo -e "$(localized_text "${YELLOW}确认后会备份现有配置，并按所选 ENTRY_MODE 生成入口配置。${PLAIN}" "${YELLOW}After confirms, it will back up the existing configuration and generate the entry configuration according to the selected ENTRY_MODE.${PLAIN}" "${YELLOW}После подтверждения он создаст резервную копию существующей конфигурации и сгенерирует конфигурацию записи в соответствии с выбранным ENTRY_MODE.${PLAIN}")"
    confirm_risk_action "$(localized_text "写入 443端口复用配置" "Write Port 443 Reuse configuration" "Запишите общую конфигурацию с повторным использованием порта 443.")" \
        "$(localized_text "${entry_label}、${web_label}配置和 443 分流规则" "${entry_label}, ${web_label} configuration and 443 routing rules" "Конфигурация ${entry_label}, ${web_label} и 443 правила маршрутизации")" \
        "$(localized_text "使用本次自动备份目录恢复，或进入 443 维护菜单回滚" "Use this automatic backup directory to restore, or enter the 443 maintenance menu to roll back" "Используйте этот каталог автоматического резервного копирования для восстановления или войдите в меню обслуживания 443 для отката.")" \
        "$(localized_text "确认公网 443 没有其他服务需要直接占用。" "Confirm that no other services on public port 443 need to be directly occupied." "Убедитесь, что никакие другие службы для публичного порта 443 не должны быть заняты напрямую.")"
}

caddy_format_configs() {
    command -v caddy >/dev/null 2>&1 || return 0
    caddy fmt --overwrite /etc/caddy/Caddyfile >/dev/null 2>&1 || true
    if [[ -d /etc/caddy/conf.d ]]; then
        while IFS= read -r conf_file; do
            caddy fmt --overwrite "$conf_file" >/dev/null 2>&1 || true
        done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)
    fi
}

sni_stack_env_path() {
    echo "/etc/vps-optimize/sni-stack.env"
}

canonical_legacy_entry_mode_name() {
    case "$1" in
        "nginx_stream") echo "nginx-stream" ;;
        "xray_fallback") echo "xray-fallback" ;;
        "tcp_peek") echo "tcp-peek" ;;
        *) return 1 ;;
    esac
}

rewrite_legacy_entry_mode_assignment() {
    local file="$1"
    local key="$2"
    local legacy_value="$3"
    local canonical_value assignment_count

    canonical_value=$(canonical_legacy_entry_mode_name "$legacy_value" 2>/dev/null) || return 1
    [[ -f "$file" && -w "$file" ]] || return 1

    assignment_count=$(grep -Ec "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null || true)
    [[ "$assignment_count" == "1" ]] || return 1
    grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*('${legacy_value}'|\"${legacy_value}\"|${legacy_value})[[:space:]]*$" "$file" 2>/dev/null || return 1

    sed -i -E \
        -e "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)'${legacy_value}'[[:space:]]*$|\\1'${canonical_value}'|" \
        -e "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)\"${legacy_value}\"[[:space:]]*$|\\1\"${canonical_value}\"|" \
        -e "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)${legacy_value}[[:space:]]*$|\\1${canonical_value}|" \
        "$file"
}

get_entry_mode() {
    local env_file mode=""
    env_file=$(sni_stack_env_path)

    if [[ ! -f "$env_file" ]]; then
        echo "not-configured"
        return 0
    fi

    mode=$(
        # shellcheck disable=SC1090
        unset ENTRY_MODE
        source "$env_file" 2>/dev/null || true
        printf '%s' "${ENTRY_MODE:-}"
    )

    case "$mode" in
        ""|"nginx-stream"|"nginx_stream")
            rewrite_legacy_entry_mode_assignment "$env_file" "ENTRY_MODE" "$mode" 2>/dev/null || true
            echo "nginx-stream"
            ;;
        "xray-fallback"|"xray_fallback")
            rewrite_legacy_entry_mode_assignment "$env_file" "ENTRY_MODE" "$mode" 2>/dev/null || true
            echo "xray-fallback"
            ;;
        "tcp-peek"|"tcp_peek")
            rewrite_legacy_entry_mode_assignment "$env_file" "ENTRY_MODE" "$mode" 2>/dev/null || true
            echo "tcp-peek"
            ;;
        *)
            echo "invalid:${mode}"
            ;;
    esac
}

print_entry_mode_compat_notice() {
    local env_file
    local state_file env_mode state_engine normalized
    env_file=$(sni_stack_env_path)
    state_file=$(single_443_engine_state_path 2>/dev/null || echo "/etc/vps-optimize/443-engine.conf")

    if [[ -f "$env_file" ]]; then
        env_mode=$(
            # shellcheck disable=SC1090
            unset ENTRY_MODE
            source "$env_file" 2>/dev/null || true
            printf '%s' "${ENTRY_MODE:-}"
        )
        if [[ -z "$env_mode" ]]; then
            echo -e "$(localized_text "${YELLOW}兼容提示：${env_file} 未写 ENTRY_MODE，已按 nginx-stream 读取；下次保存会写入 ENTRY_MODE='nginx-stream'。${PLAIN}" "${YELLOW}Compatibility tip: ${env_file} has not written ENTRY_MODE and has been read according to nginx-stream; next time it is saved, ENTRY_MODE='nginx-stream' will be written.${PLAIN}" "${YELLOW}Примечание о совместимости: ${env_file} не записал ENTRY_MODE и был прочитан в соответствии с потоком nginx; при следующем сохранении будет записано ENTRY_MODE='nginx-stream'.${PLAIN}")"
        else
            case "$env_mode" in
                "nginx_stream"|"xray_fallback"|"tcp_peek")
                    normalized=$(normalize_entry_mode_name "$env_mode" 2>/dev/null || echo "nginx-stream")
                    if ! rewrite_legacy_entry_mode_assignment "$env_file" "ENTRY_MODE" "$env_mode" 2>/dev/null; then
                        echo -e "$(localized_text "${YELLOW}兼容提示：检测到旧 ENTRY_MODE='${env_mode}'，当前按 '${normalized}' 读取；下次保存会写入新命名。${PLAIN}" "${YELLOW}Compatibility tip: The old ENTRY_MODE='${env_mode}' is detected, currently read by '${normalized}'; the new name will be written next time you save.${PLAIN}" "${YELLOW}Примечание о совместимости: обнаружен старый ENTRY_MODE='${env_mode}', который в настоящее время читается '${normalized}'; новое имя будет записано при следующем сохранении.${PLAIN}")"
                    fi
                    ;;
            esac
        fi
    fi

    if [[ -f "$state_file" ]]; then
        state_engine=$(
            # shellcheck disable=SC1090
            unset engine
            source "$state_file" 2>/dev/null || true
            printf '%s' "${engine:-}"
        )
        case "$state_engine" in
            "nginx_stream"|"xray_fallback"|"tcp_peek")
                normalized=$(normalize_entry_mode_name "$state_engine" 2>/dev/null || echo "nginx-stream")
                if ! rewrite_legacy_entry_mode_assignment "$state_file" "engine" "$state_engine" 2>/dev/null; then
                    echo -e "$(localized_text "${YELLOW}兼容提示：检测到旧 engine='${state_engine}'，当前按 '${normalized}' 读取；下次切换/重新应用会写入新命名。${PLAIN}" "${YELLOW}compatibility tip: The old engine='${state_engine}' is detected, currently read by '${normalized}'; the new name will be written next time you switch/reapply.${PLAIN}" "Совет по совместимости с ${YELLOW}: обнаружен старый engine=\"${state_engine}\", который в настоящее время читается \"${normalized}\"; новое имя будет записано при следующем переключении/повторной подаче заявки.${PLAIN}")"
                fi
                ;;
        esac
    fi
}

set_entry_mode() {
    local mode="$1"
    local env_file
    env_file=$(sni_stack_env_path)

    case "$mode" in
        "nginx_stream") mode="nginx-stream" ;;
        "xray_fallback") mode="xray-fallback" ;;
        "tcp_peek") mode="tcp-peek" ;;
    esac

    case "$mode" in
        "nginx-stream"|"xray-fallback"|"tcp-peek") ;;
        *)
            echo -e "${RED}Invalid ENTRY_MODE: ${mode}${PLAIN}"
            return 1
            ;;
    esac

    mkdir -p "$(dirname "$env_file")"
    if [[ -f "$env_file" ]] && grep -q '^ENTRY_MODE=' "$env_file" 2>/dev/null; then
        sed -i "s|^ENTRY_MODE=.*|ENTRY_MODE='${mode}'|" "$env_file"
    else
        printf "ENTRY_MODE='%s'\n" "$mode" >> "$env_file"
    fi
    chmod 600 "$env_file" 2>/dev/null || true
}

listen_process_from_ss_line() {
    local line="$1"
    local proc
    proc=$(printf '%s\n' "$line" | awk -F'"' '/users:/ {print $2; exit}')
    printf '%s' "${proc:-unknown}"
}

normalize_entry_listener_process() {
    local proc="$1"
    case "$proc" in
        nginx*) echo "nginx" ;;
        xray*|x-ui*|3x-ui*) echo "xray" ;;
        vpso-mux*|tcppeek*|tcp-peek*) echo "tcppeek" ;;
        caddy*) echo "caddy" ;;
        unknown|"") echo "unknown" ;;
        *) echo "unknown:${proc}" ;;
    esac
}

entry_listener_display_name() {
    local listener="$1"
    case "$listener" in
        nginx) echo "Nginx Stream (nginx)" ;;
        xray) echo "Xray Fallback (xray/3x-ui/x-ui)" ;;
        tcppeek) echo "$(localized_text "TCP Peek + Splice 模式 (vpso-mux 分流器)" "TCP Peek + Splice mode (vpso-mux routing)" "Режим TCP Peek + Splice (маршрутизация vpso-mux)")" ;;
        caddy) echo "$(localized_text "Caddy（不应直接接管 443端口复用）" "Caddy (should not take over the Port 443 Reuse directly)" "Caddy (не должен напрямую контролировать повторное использование порта 443)")" ;;
        none) echo "$(localized_text "未监听" "Not listening" "Не слушаю")" ;;
        multiple) echo "$(localized_text "多个进程监听/匹配" "Multiple process listening/matching" "Прослушивание/сопоставление нескольких процессов")" ;;
        unknown) echo "$(localized_text "已监听，但进程不可见" "Listened but the process is not visible" "Слушал но процесса не видно")" ;;
        unknown:*) echo "$(localized_text "未知进程 ${listener#unknown:}" "Unknown process ${listener#unknown:}" "Неизвестный процесс ${listener#unknown:}")" ;;
        *) echo "$listener" ;;
    esac
}

entry_mode_expected_listener() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode" 2>/dev/null || echo "$mode")
    case "$mode" in
        "nginx-stream") echo "nginx" ;;
        "xray-fallback") echo "xray" ;;
        "tcp-peek") echo "tcppeek" ;;
        *) echo "" ;;
    esac
}

listen_line_status() {
    local addr="$1"
    local port="$2"
    local line="$3"
    local proc

    if [[ "$addr" == "not-configured" || "$port" == "not-configured" ]]; then
        echo "$(localized_text "未配置" "Not configured" "Не настроено")"
        return 0
    fi
    if [[ -z "$line" || "$line" == "未监听" || "$line" == "not-configured" ]]; then
        echo "$(localized_text "未监听" "Not listening" "Не слушаю")"
        return 0
    fi

    proc=$(listen_process_from_ss_line "$line")
    if [[ "$proc" == "unknown" ]]; then
        echo "$(localized_text "已监听（进程不可见）" "Listened (process not visible)" "Прослушивается (процесс не виден)")"
    else
        echo "$(localized_text "已监听（${proc}）" "Monitored (${proc})" "Контролируемый (${proc})")"
    fi
}

detect_443_listener() {
    local port="${1:-${NGINX_LISTEN_PORT:-443}}"
    local lines line proc normalized seen procs
    lines=$(ss -lntp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print}' || true)

    if [[ -z "$lines" ]]; then
        echo "none|none"
        return 0
    fi

    seen=" "
    procs=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        proc=$(listen_process_from_ss_line "$line")
        normalized=$(normalize_entry_listener_process "$proc")
        if [[ "$seen" != *" ${normalized} "* ]]; then
            seen+="${normalized} "
            if [[ -z "$procs" ]]; then
                procs="$normalized"
            else
                procs="${procs},${normalized}"
            fi
        fi
    done <<< "$lines"

    if [[ "$procs" == *,* ]]; then
        echo "multiple|${procs}"
    else
        echo "${procs}|${procs}"
    fi
}

listener_info_has_entry() {
    local listener_info="$1"
    local expected="$2"
    local primary labels
    primary="${listener_info%%|*}"
    labels="${listener_info#*|}"
    [[ "$primary" == "$expected" || ",${labels}," == *",${expected},"* ]]
}

detect_current_entry_status() {
    local env_file
    local listener_info expected_listener xui_svc xui_status
    env_file=$(sni_stack_env_path)

    ENTRY_STATUS_MODE=$(get_entry_mode)
    ENTRY_STATUS_CADDY_ADDR="not-configured"
    ENTRY_STATUS_CADDY_PORT="not-configured"
    ENTRY_STATUS_XRAY_ADDR="not-configured"
    ENTRY_STATUS_XRAY_PORT="not-configured"

    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file" 2>/dev/null || true
        ENTRY_STATUS_CADDY_ADDR="${CADDY_LISTEN_ADDR:-not-configured}"
        ENTRY_STATUS_CADDY_PORT="${CADDY_LISTEN_PORT:-not-configured}"
        ENTRY_STATUS_XRAY_ADDR="${XRAY_LISTEN_ADDR:-not-configured}"
        ENTRY_STATUS_XRAY_PORT="${XRAY_LISTEN_PORT:-not-configured}"
    fi

    listener_info=$(detect_443_listener)
    ENTRY_STATUS_LISTENER="${listener_info%%|*}"
    ENTRY_STATUS_LISTENER_PROCESS="${listener_info#*|}"
    ENTRY_STATUS_LISTENER_DISPLAY=$(entry_listener_display_name "$ENTRY_STATUS_LISTENER")
    ENTRY_STATUS_NGINX_SERVICE=$(service_status_compact nginx)
    if listener_info_has_entry "$listener_info" "nginx"; then
        ENTRY_STATUS_NGINX_ROLE="$(localized_text "正在监听公网 ${NGINX_LISTEN_PORT:-443}" "listening public ${NGINX_LISTEN_PORT:-443}" "прослушивание публичной сети ${NGINX_LISTEN_PORT:-443}")"
    else
        ENTRY_STATUS_NGINX_ROLE="$(localized_text "未监听公网 ${NGINX_LISTEN_PORT:-443}；服务运行仅代表 80/其他站点或默认丢弃规则仍可用" "Not listening on the public ${NGINX_LISTEN_PORT:-443}; service operation only represents 80/other sites or the default drop rule is still available" "Не слушаю публичную сеть ${NGINX_LISTEN_PORT:-443}; операция службы представляет только 80/другие сайты, или правило удаления по умолчанию все еще доступно")"
    fi
    xui_status=$(xui_panel_status_compact)
    if xui_svc=$(xui_panel_service_name 2>/dev/null); then
        xui_status="${xui_svc}.service ${xui_status}"
    fi
    ENTRY_STATUS_XRAY_SERVICE="$(localized_text "面板托管 Xray: ${xui_status} / 独立 xray.service: $(service_status_compact xray)" "Panel hosting Xray: ${xui_status} / Standalone xray.service: $(service_status_compact xray)" "Хостинг панели Xray: ${xui_status} / Автономный xray.service: $(service_status_compact xray)")"
    ENTRY_STATUS_TCPPEEK_SERVICE=$(service_status_compact vpso-mux)
    ENTRY_STATUS_CADDY_LISTEN_LINE="not-configured"
    ENTRY_STATUS_XRAY_LISTEN_LINE="not-configured"

    if is_valid_port "$ENTRY_STATUS_CADDY_PORT"; then
        ENTRY_STATUS_CADDY_LISTEN_LINE=$(get_listen_line_by_port "$ENTRY_STATUS_CADDY_PORT")
    fi
    if is_valid_port "$ENTRY_STATUS_XRAY_PORT"; then
        ENTRY_STATUS_XRAY_LISTEN_LINE=$(get_listen_line_by_port "$ENTRY_STATUS_XRAY_PORT")
    fi

    expected_listener=$(entry_mode_expected_listener "$ENTRY_STATUS_MODE")

    if [[ -n "$expected_listener" ]] && listener_info_has_entry "$listener_info" "$expected_listener"; then
        ENTRY_STATUS_CONSISTENT="yes"
    else
        ENTRY_STATUS_CONSISTENT="no"
    fi
}

show_current_entry_status() {
    detect_current_entry_status
    local web_engine web_label
    web_engine=$(normalize_web_proxy_engine "${WEB_PROXY_ENGINE:-caddy}" 2>/dev/null || echo "caddy")
    web_label=$(web_proxy_engine_label "$web_engine")
    echo -e "$(localized_text "${BOLD}当前 443 入口状态${PLAIN}" "${BOLD}Current 443 entry status${PLAIN}" "${BOLD}текущий статус записи 443${PLAIN}")"
    echo -e "$(localized_text "配置模式：${CYAN}${ENTRY_STATUS_MODE}${PLAIN}" "Configuration mode: ${CYAN}${ENTRY_STATUS_MODE}${PLAIN}" "Режим конфигурации: ${CYAN}${ENTRY_STATUS_MODE}${PLAIN}")"
    echo -e "$(localized_text "Web 反代：${web_label} (${web_engine})" "Web reverse proxy: ${web_label} (${web_engine})" "веб-прокси: ${web_label} (${web_engine})")"
    print_entry_mode_compat_notice
    echo -e "$(localized_text "公网 443：${ENTRY_STATUS_LISTENER_DISPLAY}" "public port 443: ${ENTRY_STATUS_LISTENER_DISPLAY}" "публичный порт 443: ${ENTRY_STATUS_LISTENER_DISPLAY}")"
    echo -e "$(localized_text "监听进程：${ENTRY_STATUS_LISTENER_PROCESS}" "Listening process: ${ENTRY_STATUS_LISTENER_PROCESS}" "Процесс прослушивания: ${ENTRY_STATUS_LISTENER_PROCESS}")"
    if [[ "$ENTRY_STATUS_LISTENER" == "xray" ]]; then
        echo -e "$(localized_text "Xray 公网：${GREEN}公网 443 当前由 Xray/面板托管 Xray 监听${PLAIN}" "Xray Internet: ${GREEN} public port 443 currently hosted by Xray/panel Xray listening on ${PLAIN}" "Xray Публичная сеть: ${GREEN}публичный порт 443 в настоящее время размещается на Xray/панель Xray контролирует${PLAIN}")"
    else
        echo -e "$(localized_text "Xray 公网：未检测到 Xray 监听公网 443" "Xray public: Not detected Xray listening public port 443" "Xray Публичная сеть: не обнаружена Xray прослушивание публичного порта 443")"
    fi
    if [[ "$ENTRY_STATUS_CONSISTENT" == "yes" ]]; then
        echo -e "$(localized_text "一致性：${GREEN}配置模式与实际监听一致${PLAIN}" "Consistency: ${GREEN}Configuration mode is consistent with actual listening${PLAIN}" "Согласованность: режим конфигурации ${GREEN}соответствует реальному прослушиваниеу${PLAIN}.")"
    else
        echo -e "$(localized_text "一致性：${YELLOW}配置模式与实际监听不一致${PLAIN}" "Consistency: ${YELLOW}Configuration mode is inconsistent with actual listening${PLAIN}" "Согласованность: режим конфигурации ${YELLOW}не соответствует фактическому прослушиваниеу${PLAIN}.")"
        echo -e "$(localized_text "${YELLOW}配置模式与实际监听不一致，建议重新应用当前入口模式。${PLAIN}" "${YELLOW}Configuration mode is inconsistent with actual listening. It is recommended to re-apply the current entry mode.${PLAIN}" "${YELLOW}Режим конфигурации несовместим с реальным прослушиваниеом. Рекомендуется повторно применить текущий режим входа.${PLAIN}")"
    fi
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}本地监听${PLAIN}" "${BOLD}Local listeners${PLAIN}" "${BOLD}локальный прослушивание${PLAIN}")"
    echo -e "$(localized_text "Web 反代：${ENTRY_STATUS_CADDY_ADDR}:${ENTRY_STATUS_CADDY_PORT} - $(listen_line_status "$ENTRY_STATUS_CADDY_ADDR" "$ENTRY_STATUS_CADDY_PORT" "$ENTRY_STATUS_CADDY_LISTEN_LINE")" "Web reverse proxy: ${ENTRY_STATUS_CADDY_ADDR}:${ENTRY_STATUS_CADDY_PORT} - $(listen_line_status \"$ENTRY_STATUS_CADDY_ADDR\" \"$ENTRY_STATUS_CADDY_PORT\" \"$ENTRY_STATUS_CADDY_LISTEN_LINE\")" "веб-прокси: ${ENTRY_STATUS_CADDY_ADDR}:${ENTRY_STATUS_CADDY_PORT} - $(listen_line_status \"$ENTRY_STATUS_CADDY_ADDR\" \"$ENTRY_STATUS_CADDY_PORT\" \"$ENTRY_STATUS_CADDY_LISTEN_LINE\")")"
    echo -e "Xray： ${ENTRY_STATUS_XRAY_ADDR}:${ENTRY_STATUS_XRAY_PORT} - $(listen_line_status "$ENTRY_STATUS_XRAY_ADDR" "$ENTRY_STATUS_XRAY_PORT" "$ENTRY_STATUS_XRAY_LISTEN_LINE")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}服务状态${PLAIN}" "${BOLD}Service status${PLAIN}" "${BOLD}Состояние обслуживания${PLAIN}")"
    echo -e "nginx：${ENTRY_STATUS_NGINX_SERVICE}（${ENTRY_STATUS_NGINX_ROLE}）"
    echo -e "$(localized_text "TCP Peek + Splice / vpso-mux 分流器：${ENTRY_STATUS_TCPPEEK_SERVICE}" "TCP Peek + Splice / vpso-mux routing: ${ENTRY_STATUS_TCPPEEK_SERVICE}" "TCP Peek + Splice / vpso-mux маршрутизация: ${ENTRY_STATUS_TCPPEEK_SERVICE}")"
    echo -e "Xray/3x-ui/x-ui：${ENTRY_STATUS_XRAY_SERVICE}"
}

show_current_entry_summary() {
    detect_current_entry_status
    echo -e "$(localized_text "${BOLD}当前入口模式：${CYAN}${ENTRY_STATUS_MODE}${PLAIN}" "${BOLD}Current entry mode: ${ENTRY_STATUS_MODE}${PLAIN}" "${BOLD}Текущий режим ввода: ${ENTRY_STATUS_MODE}${PLAIN}")"
    print_entry_mode_compat_notice
    if [[ "$ENTRY_STATUS_CONSISTENT" != "yes" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 配置模式与公网 443 实际监听不一致，详情看 [1]，建议确认后重新应用当前入口模式。${PLAIN}" "${YELLOW}⚠️ The configuration mode is inconsistent with the actual listening of public port 443. For details, see [1]. It is recommended to re-apply the current entry mode after confirmation.${PLAIN}" "${YELLOW}⚠️ Режим настройки не соответствует фактическому прослушиваниеу публичного порта 443. Подробности см. в [1]. После подтверждения рекомендуется повторно применить текущий режим входа.${PLAIN}")"
    fi
}

load_sni_stack_env() {
    local env_file
    env_file=$(sni_stack_env_path)
    if [[ ! -f "$env_file" ]]; then
        echo -e "$(localized_text "${RED}❌ 未找到 ${env_file}，请运行主菜单 [19] -> [2] 安装 443 入口。${PLAIN}" "${RED}❌ ${env_file} was not found. Run main menu [19] -> [2] to install the 443 entry.${PLAIN}" "${RED}❌ Файл ${env_file} не найден. Запустите главное меню [19] -> [2], чтобы установить вход 443.${PLAIN}")"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$env_file"
    ENTRY_MODE=$(get_entry_mode)
    STRICT_SNI_GATE=$(normalize_strict_sni_gate "${STRICT_SNI_GATE:-false}")
    WEB_PROXY_ENGINE=$(normalize_web_proxy_engine "${WEB_PROXY_ENGINE:-caddy}" 2>/dev/null || echo "caddy")
    PANEL_WEB_PATH=$(normalize_path_prefix "${PANEL_WEB_PATH:-/panel/}")
    SUB_URI_PATH=$(normalize_path_prefix "${SUB_URI_PATH:-/sub/}")
    CLASH_URI_PATH=$(normalize_path_prefix "${CLASH_URI_PATH:-/clash/}")
    normalize_site_stack_arrays
    normalize_tcp_route_arrays
    load_xray_sni_route_arrays
    normalize_sni_ip_whitelist_arrays
}

get_listen_line_by_port() {
    local port="$1"
    local line
    line=$(ss -lntp 2>/dev/null | grep ":${port}[[:space:]]" | head -n1 || true)
    echo "$(localized_text "${line:-未监听}" "${line:-未监听}" "${line:-未监听}")"
}

print_sni_stack_current_summary() {
    local env_file="/etc/vps-optimize/sni-stack.env"
    local caddy_conf="/etc/caddy/conf.d/${PANEL_DOMAIN}.caddy"
    local nginx_web_conf="/etc/nginx/conf.d/vps_sni_web_${CADDY_LISTEN_PORT}.conf"
    local nginx_conf="/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf"
    local web_engine web_label web_backend
    web_engine=$(current_web_proxy_engine)
    web_label=$(web_proxy_engine_label "$web_engine")
    web_backend=$(web_proxy_backend)

    echo -e "$(localized_text "${BOLD}当前保存的 443 分流配置${PLAIN} ${CYAN}(${env_file})${PLAIN}" "${BOLD}Currently saved 443 routing configuration (${env_file})${PLAIN}" "${BOLD}На данный момент сохранено 443 конфигурации маршрутизации (${env_file})${PLAIN}")"
    echo -e "$(localized_text "面板：      https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Panel: https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "Панель: https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}")"
    echo -e "$(localized_text "普通订阅：  https://${PANEL_DOMAIN}${SUB_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Ordinary subscription: https://${PANEL_DOMAIN}${SUB_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Обычная подписка: https://${PANEL_DOMAIN}${SUB_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}")"
    echo -e "$(localized_text "Clash 订阅：https://${PANEL_DOMAIN}${CLASH_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Clash Subscribe: https://${PANEL_DOMAIN}${CLASH_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Clash Подписаться: https://${PANEL_DOMAIN}${CLASH_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}")"
    echo -e "REALITY：   ${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "TCP/SNI：   ${TCP_ROUTE_SNIS[$tcp_i]} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "Xray 入站：  ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "Xray Inbound: ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "Xray Входящий: ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}")"
        done
    fi
    echo -e "$(localized_text "Web 反代：  ${web_label} (${web_backend})" "Web reverse proxy: ${web_label} (${web_backend})" "веб-прокси: ${web_label} (${web_backend})")"
    echo -e "$(localized_text "公网入口：  ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${web_label} ${web_backend}" "public entry: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${web_label} ${web_backend}" "Вход в публичную сеть: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${web_label} ${web_backend}")"
    echo -e "$(localized_text "配置文件：  Nginx ${nginx_conf}" "Configuration file: Nginx ${nginx_conf}" "Файл конфигурации: Nginx ${nginx_conf}")"
    if [[ "$web_engine" == "nginx" ]]; then
        echo -e "           Nginx Web ${nginx_web_conf}"
    else
        echo -e "           Caddy ${caddy_conf}"
    fi
    print_sni_ip_whitelist_summary
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}当前实际监听状态${PLAIN}" "${BOLD}Current actual listening status${PLAIN}" "${BOLD}Текущий фактический статус прослушивания${PLAIN}")"
    echo -e "$(localized_text "Nginx 入口：  $(get_listen_line_by_port "$NGINX_LISTEN_PORT")" "Nginx entry: $(get_listen_line_by_port \"$NGINX_LISTEN_PORT\")" "Nginx Вход: $(get_listen_line_by_port \"$NGINX_LISTEN_PORT\")")"
    echo -e "${web_label}：$(get_listen_line_by_port "$CADDY_LISTEN_PORT")"
    echo -e "$(localized_text "面板后端：    $(get_listen_line_by_port "$PANEL_LISTEN_PORT")" "Panel backend: $(get_listen_line_by_port \"$PANEL_LISTEN_PORT\")" "бэкенд панели: $(get_listen_line_by_port \"$PANEL_LISTEN_PORT\")")"
    echo -e "$(localized_text "订阅后端：    $(get_listen_line_by_port "$SUB_LISTEN_PORT")" "Subscription backend: $(get_listen_line_by_port \"$SUB_LISTEN_PORT\")" "Сервер подписки: $(get_listen_line_by_port \"$SUB_LISTEN_PORT\")")"
    echo -e "$(localized_text "REALITY 后端：$(get_listen_line_by_port "$XRAY_LISTEN_PORT")" "REALITY Backend: $(get_listen_line_by_port \"$XRAY_LISTEN_PORT\")" "REALITY бэкенд: $(get_listen_line_by_port \"$XRAY_LISTEN_PORT\")")"
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "TCP/SNI 后端 ${TCP_ROUTE_SNIS[$tcp_i]}：$(get_listen_line_by_port "${TCP_ROUTE_PORTS[$tcp_i]}")" "TCP/SNI backend ${TCP_ROUTE_SNIS[$tcp_i]}: $(get_listen_line_by_port \"${TCP_ROUTE_PORTS[$tcp_i]}\")" "TCP/SNI бэкенд ${TCP_ROUTE_SNIS[$tcp_i]}: $(get_listen_line_by_port \"${TCP_ROUTE_PORTS[$tcp_i]}\")")"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "$(localized_text "Xray 入站后端 ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}：$(get_listen_line_by_port "${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}")" "Xray Inbound backend ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}: $(get_listen_line_by_port \"${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}\")" "Xray Входящая бэкенд ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}: $(get_listen_line_by_port \"${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}\")")"
        done
    fi
}

normalize_site_stack_arrays() {
    SITE_DOMAINS=()
    SITE_BACKEND_ADDRS=()
    SITE_BACKEND_PORTS=()

    if [[ -n "${SITE_DOMAINS_CSV:-}" ]]; then
        split_csv_to_array "$SITE_DOMAINS_CSV" SITE_DOMAINS
        split_csv_to_array "${SITE_BACKEND_ADDRS_CSV:-}" SITE_BACKEND_ADDRS
        split_csv_to_array "${SITE_BACKEND_PORTS_CSV:-}" SITE_BACKEND_PORTS
    elif [[ -n "${SITE_DOMAIN:-}" ]]; then
        SITE_DOMAINS=("$SITE_DOMAIN")
        SITE_BACKEND_ADDRS=("${SITE_BACKEND_ADDR:-127.0.0.1}")
        SITE_BACKEND_PORTS=("${SITE_BACKEND_PORT:-3000}")
    fi

    local i default_port
    default_port=3000
    for i in "${!SITE_DOMAINS[@]}"; do
        SITE_DOMAINS[$i]=$(normalize_domain_input "${SITE_DOMAINS[$i]}")
        SITE_BACKEND_ADDRS[$i]="${SITE_BACKEND_ADDRS[$i]:-127.0.0.1}"
        if [[ -z "${SITE_BACKEND_PORTS[$i]:-}" ]]; then
            if [[ "$i" -eq 0 && -n "${SITE_BACKEND_PORT:-}" ]]; then
                SITE_BACKEND_PORTS[$i]="$SITE_BACKEND_PORT"
            else
                SITE_BACKEND_PORTS[$i]="$default_port"
            fi
        fi
        SITE_BACKEND_ADDRS[$i]=$(normalize_backend_addr_input "${SITE_BACKEND_ADDRS[$i]}")
        SITE_BACKEND_PORTS[$i]=$(normalize_port_input "${SITE_BACKEND_PORTS[$i]}")
        default_port=$((default_port + 1))
    done

    SITE_DOMAIN="${SITE_DOMAINS[0]:-}"
    SITE_BACKEND_ADDR="${SITE_BACKEND_ADDRS[0]:-127.0.0.1}"
    SITE_BACKEND_PORT="${SITE_BACKEND_PORTS[0]:-3000}"
}

normalize_tcp_route_arrays() {
    local -a raw_snis=()
    local -a raw_addrs=()
    local -a raw_ports=()
    local -a clean_snis=()
    local -a clean_addrs=()
    local -a clean_ports=()
    local i sni addr port

    if [[ -n "${TCP_ROUTE_SNIS_CSV:-}" ]]; then
        split_csv_to_array "$TCP_ROUTE_SNIS_CSV" raw_snis
        split_csv_to_array "${TCP_ROUTE_ADDRS_CSV:-}" raw_addrs
        split_csv_to_array "${TCP_ROUTE_PORTS_CSV:-}" raw_ports
    fi

    for i in "${!raw_snis[@]}"; do
        sni=$(normalize_domain_input "${raw_snis[$i]}")
        addr=$(normalize_loopback_addr "$(normalize_ip_input "${raw_addrs[$i]:-127.0.0.1}")")
        port=$(normalize_port_input "${raw_ports[$i]:-8443}")
        if is_valid_domain "$sni" && is_loopback_listen_addr "$addr" && is_valid_port "$port"; then
            clean_snis+=("$sni")
            clean_addrs+=("$addr")
            clean_ports+=("$port")
        fi
    done

    TCP_ROUTE_SNIS=("${clean_snis[@]}")
    TCP_ROUTE_ADDRS=("${clean_addrs[@]}")
    TCP_ROUTE_PORTS=("${clean_ports[@]}")
}

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
    echo -e "$(localized_text "${YELLOW}如果 Web 域名开启 CDN/WAF/源站保护/Cloudflare 回源限制/Web 白名单，403 或拒绝访问通常是 Web/CDN/白名单/SNI 策略阻断，不一定是证书或反代引擎故障。${PLAIN}" "${YELLOW}If the Web domain has CDN/WAF/origin protection/Cloudflare return-to-origin restriction/Web whitelist, 403 or access denied is usually blocked by the Web/CDN/whitelist/SNI policy, and is not necessarily a certificate or reverse proxy engine failure.${PLAIN}" "${YELLOW}Если имя веб-домена имеет CDN/WAF/защиту исходного сайта/ограничения исходного сайта серверной части подключения Cloudflare/белый список веб-сайтов, 403 или отказ в доступе обычно блокируется политикой Интернета/CDN/белого списка/SNI и не обязательно является сбоем сертификата или механизма обратного прокси-сервера.${PLAIN}")"
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

is_sni_stack_managed_domain() {
    local domain="$1"
    local site_domain
    [[ "$domain" == "$PANEL_DOMAIN" ]] && return 0
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    for site_domain in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    for site_domain in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    return 1
}

is_sni_stack_web_domain() {
    local domain="$1"
    local site_domain
    [[ "$domain" == "$PANEL_DOMAIN" ]] && return 0
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    return 1
}

nginx_var_suffix_for_domain() {
    local domain="$1"
    domain=$(echo "$domain" | tr '.-' '__' | tr -cd 'a-zA-Z0-9_')
    printf '%s' "$domain"
}

normalize_sni_ip_whitelist_arrays() {
    local domains_input="${SNI_IP_WHITELIST_DOMAINS_CSV:-}"
    local ranges_input="${SNI_IP_WHITELIST_RANGES_PIPE:-}"
    local -a raw_domains=()
    local -a raw_ranges=()
    local -a clean_domains=()
    local -a clean_ranges=()
    local -a range_array=()
    local i domain ranges

    SNI_IP_WHITELIST_DOMAINS=()
    SNI_IP_WHITELIST_RANGES=()

    [[ -n "$domains_input" ]] && split_csv_to_array "$domains_input" raw_domains
    [[ -n "$ranges_input" ]] && split_pipe_to_array "$ranges_input" raw_ranges

    for i in "${!raw_domains[@]}"; do
        domain=$(normalize_domain_input "${raw_domains[$i]}")
        ranges="${raw_ranges[$i]:-}"
        [[ -n "$domain" && -n "$ranges" ]] || continue
        is_valid_domain "$domain" || continue
        is_sni_stack_web_domain "$domain" || continue
        if normalize_ip_whitelist_input "$ranges" range_array; then
            clean_domains+=("$domain")
            clean_ranges+=("$(join_array_by_space "${range_array[@]}")")
        fi
    done

    SNI_IP_WHITELIST_DOMAINS=("${clean_domains[@]}")
    SNI_IP_WHITELIST_RANGES=("${clean_ranges[@]}")
}

sni_ip_whitelist_index() {
    local domain="$1"
    local i
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        [[ "$domain" == "${SNI_IP_WHITELIST_DOMAINS[$i]}" ]] && { echo "$i"; return 0; }
    done
    return 1
}

sni_ip_whitelist_ranges_for_domain() {
    local domain="$1"
    local idx
    idx=$(sni_ip_whitelist_index "$domain" 2>/dev/null) || return 0
    echo "${SNI_IP_WHITELIST_RANGES[$idx]:-}"
}

set_sni_ip_whitelist_for_domain() {
    local domain="$1"
    local ranges="$2"
    local idx
    idx=$(sni_ip_whitelist_index "$domain" 2>/dev/null) || idx=""
    if [[ -n "$idx" ]]; then
        SNI_IP_WHITELIST_RANGES[$idx]="$ranges"
    else
        SNI_IP_WHITELIST_DOMAINS+=("$domain")
        SNI_IP_WHITELIST_RANGES+=("$ranges")
    fi
}

remove_sni_ip_whitelist_for_domain() {
    local domain="$1"
    local i
    local -a new_domains=()
    local -a new_ranges=()
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        [[ "$domain" == "${SNI_IP_WHITELIST_DOMAINS[$i]}" ]] && continue
        new_domains+=("${SNI_IP_WHITELIST_DOMAINS[$i]}")
        new_ranges+=("${SNI_IP_WHITELIST_RANGES[$i]}")
    done
    SNI_IP_WHITELIST_DOMAINS=("${new_domains[@]}")
    SNI_IP_WHITELIST_RANGES=("${new_ranges[@]}")
}

rename_sni_ip_whitelist_domain() {
    local old_domain="$1"
    local new_domain="$2"
    local idx
    idx=$(sni_ip_whitelist_index "$old_domain" 2>/dev/null) || return 0
    SNI_IP_WHITELIST_DOMAINS[$idx]="$new_domain"
}

print_sni_ip_whitelist_summary() {
    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -eq 0 ]]; then
        echo -e "$(localized_text "IP 白名单：  未启用" "IP Whitelist: Not enabled" "Белый список IP: не включен")"
        return 0
    fi

    local i
    echo -e "$(localized_text "IP 白名单：" "IP whitelist:" "Белый список IP:")"
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        echo -e "$(localized_text "  - ${SNI_IP_WHITELIST_DOMAINS[$i]} 仅允许：${SNI_IP_WHITELIST_RANGES[$i]}" "- ${SNI_IP_WHITELIST_DOMAINS[$i]} Only allowed: ${SNI_IP_WHITELIST_RANGES[$i]}" "- ${SNI_IP_WHITELIST_DOMAINS[$i]} Разрешено только: ${SNI_IP_WHITELIST_RANGES[$i]}")"
    done
}

sni_stack_health_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧪 443端口复用链路体检${PLAIN}" "${BOLD}🧪 Port 443 Reuse routing link health check${PLAIN}" "${BOLD}🧪 Проверка маршрутизации повторного использования порта 443${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local current_mode
    current_mode=$(get_entry_mode)
    if [[ "$current_mode" != "nginx-stream" ]]; then
        sni_stack_health_check_enhanced
        return $?
    fi

    local ok=0 warn=0 fail=0
    check_listen() {
        local name="$1"
        local port="$2"
        local expect_addr="$3"
        if ss -lntp 2>/dev/null | grep -q ":${port}[[:space:]]"; then
            local line
            line=$(ss -lntp 2>/dev/null | grep ":${port}[[:space:]]" | head -n1)
            echo -e "$(localized_text "${GREEN}✅ ${name} 端口 ${port} 有监听：${line}${PLAIN}" "${GREEN}✅ ${name} port ${port} is monitored: ${line}${PLAIN}" "${GREEN}✅ ${name} Порт ${port} контролируется: ${line}${PLAIN}")"
            if [[ -n "$expect_addr" ]] && ! echo "$line" | grep -q "$expect_addr"; then
                echo -e "$(localized_text "${YELLOW}⚠️ ${name} 期望监听 ${expect_addr}:${port}，请确认是否被改成公网监听。${PLAIN}" "${YELLOW}⚠️ ${name} is expected to monitor ${expect_addr}:${port}, please confirm whether it has been changed to Internet listening.${PLAIN}" "${YELLOW}⚠️ ${name} планирует отслеживать ${expect_addr}:${port}. Пожалуйста, подтвердите, был ли он изменен на прослушивание публичной сети.${PLAIN}")"
                ((warn++))
            else
                ((ok++))
            fi
        else
            echo -e "$(localized_text "${RED}❌ ${name} 端口 ${port} 未监听。${PLAIN}" "${RED}❌ ${name} Port ${port} is not listening.${PLAIN}" "${RED}❌ ${name} Порт ${port} не прослушивается.${PLAIN}")"
            ((fail++))
        fi
    }
    check_backend() {
        local name="$1"
        local addr="$2"
        local port="$3"
        local probe_rc

        if probe_backend_target "$name" "$addr" "$port"; then
            ((ok++))
            return 0
        fi
        probe_rc=$?
        if [[ "$probe_rc" -eq 2 ]]; then
            ((warn++))
        else
            ((fail++))
        fi
    }

    check_listen "$(localized_text "Nginx 公网入口" "Nginx public entry" "Nginx вход в публичную сеть")" "$NGINX_LISTEN_PORT" ""
    check_listen "$(localized_text "$(web_proxy_engine_label) 本地 TLS" "$(web_proxy_engine_label) local TLS" "$(web_proxy_engine_label) локальный TLS")" "$CADDY_LISTEN_PORT" "$CADDY_LISTEN_ADDR"
    check_listen "Xray / 3x-ui+Reality" "$XRAY_LISTEN_PORT" "$XRAY_LISTEN_ADDR"
    check_listen "$(localized_text "3x-ui 面板" "3x-ui panel" "Панель 3x-ui")" "$PANEL_LISTEN_PORT" "$PANEL_LISTEN_ADDR"
    check_listen "$(localized_text "3x-ui 订阅" "3x-ui Subscribe" "3x-ui Подписаться")" "$SUB_LISTEN_PORT" "$SUB_LISTEN_ADDR"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            check_backend "$(localized_text "网站后端 ${SITE_DOMAINS[$i]}" "Website backend ${SITE_DOMAINS[$i]}" "бэкенд сайта ${SITE_DOMAINS[$i]}")" "${SITE_BACKEND_ADDRS[$i]}" "${SITE_BACKEND_PORTS[$i]}"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            check_listen "$(localized_text "TCP/SNI 入站 ${TCP_ROUTE_SNIS[$tcp_i]}" "TCP/SNI Inbound ${TCP_ROUTE_SNIS[$tcp_i]}" "TCP/SNI Входящий ${TCP_ROUTE_SNIS[$tcp_i]}")" "${TCP_ROUTE_PORTS[$tcp_i]}" "${TCP_ROUTE_ADDRS[$tcp_i]}"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            check_listen "$(localized_text "Xray 入站 ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}" "Xray Inbound ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}" "Xray Входящий ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}")" "${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}"
        done
    fi

    echo -e "------------------------------------------------"
    if check_xui_cert_settings_for_single_443; then
        ((ok++))
    else
        ((warn++))
    fi

    echo -e "------------------------------------------------"
    if check_domain_dns_sanity "$PANEL_DOMAIN" "$(localized_text "面板域名" "Panel domain" "Доменное имя панели")" "warn"; then
        ((ok++))
    else
        ((warn++))
    fi
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local dns_site
        for dns_site in "${SITE_DOMAINS[@]}"; do
            [[ -z "$dns_site" ]] && continue
            if check_domain_dns_sanity "$dns_site" "$(localized_text "网站/反代域名" "Website/reverse domain" "Веб-сайт/обратное доменное имя")" "warn"; then
                ((ok++))
            else
                ((warn++))
            fi
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_sni
        for tcp_sni in "${TCP_ROUTE_SNIS[@]}"; do
            [[ -z "$tcp_sni" ]] && continue
            if check_domain_dns_sanity "$tcp_sni" "$(localized_text "TCP/SNI 入站域名" "TCP/SNI inbound domain" "TCP/SNI имя входящего домена")" "warn"; then
                ((ok++))
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 如果客户端使用服务器 IP 连接并手动指定 SNI，可忽略该 DNS 警告。${PLAIN}" "${YELLOW}⚠️ This DNS warning can be ignored if the client connects using the server IP and manually specifies SNI.${PLAIN}" "${YELLOW}⚠️ Это предупреждение DNS можно игнорировать, если клиент подключается с использованием IP-адреса сервера и вручную указывает SNI.${PLAIN}")"
                ((warn++))
            fi
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_sni
        for xray_route_sni in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
            [[ -z "$xray_route_sni" ]] && continue
            if check_domain_dns_sanity "$xray_route_sni" "$(localized_text "Xray 入站域名" "Xray inbound domain" "Xray входящее доменное имя")" "warn"; then
                ((ok++))
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 如果客户端使用服务器 IP 连接并手动指定 SNI，可忽略该 DNS 警告。${PLAIN}" "${YELLOW}⚠️ This DNS warning can be ignored if the client connects using the server IP and manually specifies SNI.${PLAIN}" "${YELLOW}⚠️ Это предупреждение DNS можно игнорировать, если клиент подключается с использованием IP-адреса сервера и вручную указывает SNI.${PLAIN}")"
                ((warn++))
            fi
        done
    fi

    echo -e "------------------------------------------------"
    nginx -t >/dev/null 2>&1 && echo -e "$(localized_text "${GREEN}✅ nginx -t 通过${PLAIN}" "${GREEN}✅ nginx -t by${PLAIN}" "${GREEN}✅ nginx -t от${PLAIN}")" && ((ok++)) || { echo -e "$(localized_text "${RED}❌ nginx -t 失败${PLAIN}" "${RED}❌ nginx -t failed${PLAIN}" "${RED}❌ nginx -t не удалось${PLAIN}")"; ((fail++)); }
    if [[ "$(current_web_proxy_engine)" == "caddy" ]]; then
        caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 && echo -e "$(localized_text "${GREEN}✅ Caddy 配置校验通过${PLAIN}" "${GREEN}✅ Caddy configuration validation passed${PLAIN}" "${GREEN}✅ Проверка конфигурации Caddy пройдена${PLAIN}")" && ((ok++)) || { echo -e "$(localized_text "${RED}❌ Caddy 配置校验失败${PLAIN}" "${RED}❌ Caddy configuration validation failed${PLAIN}" "${RED}❌ Caddy Проверка конфигурации не удалась${PLAIN}")"; ((fail++)); }
    fi
    if grep -Eq '^[[:space:]]*server_tokens[[:space:]]+off;' /etc/nginx/nginx.conf 2>/dev/null; then
        echo -e "$(localized_text "${GREEN}✅ Nginx 已关闭版本号显示 server_tokens off${PLAIN}" "${GREEN}✅ Nginx Version number display has been turned off server_tokens off${PLAIN}" "${GREEN}✅ Nginx Отображение номера версии отключено server_tokens off${PLAIN}")"
        ((ok++))
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未确认 Nginx server_tokens off，错误页可能显示版本号。${PLAIN}" "${YELLOW}⚠️ Not confirmed Nginx server_tokens off, the error page may display the version number.${PLAIN}" "${YELLOW}⚠️ Не подтверждено. Nginx server_tokens отключен, на странице ошибки может отображаться номер версии.${PLAIN}")"
        ((warn++))
    fi
    if [[ -f /etc/nginx/conf.d/00-vps-default-drop.conf ]]; then
        echo -e "$(localized_text "${GREEN}✅ Nginx 80 默认站点已设置为丢弃连接${PLAIN}" "${GREEN}✅ Nginx 80 The default site has been set to drop connections${PLAIN}" "${GREEN}✅ Nginx 80 Сайт по умолчанию настроен на отбрасывание соединений${PLAIN}")"
        ((ok++))
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未找到 80 默认丢弃配置，错误域名可能命中默认页。${PLAIN}" "${YELLOW}⚠️ Not found 80 default discard configuration, wrong domain may hit the default page.${PLAIN}" "${YELLOW}⚠️ Не найдено 80. Конфигурация отмены по умолчанию, неправильное доменное имя может попасть на страницу по умолчанию.${PLAIN}")"
        ((warn++))
    fi

    if command -v openssl >/dev/null 2>&1; then
        if timeout 10 openssl s_client -connect "127.0.0.1:${NGINX_LISTEN_PORT}" -servername "$PANEL_DOMAIN" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
            echo -e "$(localized_text "${GREEN}✅ 面板 SNI 可从入口命中 Web 反代引擎证书链${PLAIN}" "${GREEN}✅ Panel SNI can hit the Web reverse proxy engine certificate chain from the entry${PLAIN}" "${GREEN}✅ Панель SNI может попасть в цепочку сертификатов механизма обратного веб-прокси  со входа.${PLAIN}")"
            ((ok++))
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 面板 SNI 测试未拿到证书，请检查入口模式与 Web 反代引擎。${PLAIN}" "${YELLOW}⚠️ Panel SNI test did not get the certificate, please check the entry mode and Web reverse proxy engine.${PLAIN}" "${YELLOW}⚠️ Тест панели SNI не получил сертификат, проверьте режим входа и механизм веб-прокси.${PLAIN}")"
            ((warn++))
        fi
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "体检结果：${GREEN}通过 ${ok}${PLAIN} / ${YELLOW}警告 ${warn}${PLAIN} / ${RED}失败 ${fail}${PLAIN}" "health check results: ${GREEN}Passed ${ok}${PLAIN} / ${YELLOW}Warning ${warn}${PLAIN} / ${RED}Failed ${fail}${PLAIN}" "Результаты медицинского осмотра: ${GREEN}прошел ${ok}${PLAIN} / ${YELLOW}предупреждение ${warn}${PLAIN} / ${RED}не прошел ${fail}${PLAIN}")"
}
