# shellcheck shell=bash
# vpso-mux paths, engine state, route summaries, and runtime status output.

vpso_mux_config_path() {
    echo "/etc/vps-optimize/vpso-mux.yaml"
}

vpso_mux_service_name() {
    echo "vpso-mux.service"
}

vpso_mux_status_json_path() {
    echo "/var/lib/vps-optimize/vpso-mux/status.json"
}

single_443_engine_state_path() {
    echo "/etc/vps-optimize/443-engine.conf"
}

yaml_quote() {
    local value="$1"
    value=$(printf '%s' "$value" | sed "s/'/''/g")
    printf "'%s'" "$value"
}

single_443_current_engine() {
    local state_file raw_engine env_mode normalized
    state_file=$(single_443_engine_state_path)
    if [[ -f "$state_file" ]]; then
        raw_engine=$(
            # shellcheck disable=SC1090
            unset engine
            source "$state_file" 2>/dev/null || true
            printf '%s' "${engine:-}"
        )
        if [[ -n "$raw_engine" ]]; then
            normalized=$(normalize_entry_mode_name "$raw_engine" 2>/dev/null || true)
            if [[ -n "$normalized" ]]; then
                if declare -F rewrite_legacy_entry_mode_assignment >/dev/null 2>&1; then
                    rewrite_legacy_entry_mode_assignment "$state_file" "engine" "$raw_engine" 2>/dev/null || true
                fi
                printf '%s' "$normalized"
            else
                printf 'invalid:%s' "$raw_engine"
            fi
            return 0
        fi
    fi
    env_mode=$(get_entry_mode)
    case "$env_mode" in
        "nginx-stream"|"xray-fallback"|"tcp-peek") printf '%s' "$env_mode" ;;
        *) printf 'nginx-stream' ;;
    esac
}

sni_stack_route_name() {
    local prefix="$1"
    local sni="$2"
    sni=$(echo "$sni" | tr '.-' '__' | tr -cd 'a-zA-Z0-9_')
    printf '%s_%s' "$prefix" "$sni"
}

sni_stack_route_summary_for_state() {
    local web_backend xray_backend summary i domain
    web_backend=$(web_proxy_backend)
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    if strict_sni_gate_enabled; then
        summary="panel:${PANEL_DOMAIN}->${web_backend},reality:${REALITY_SNI}->${xray_backend},default->reject"
    else
        summary="panel:${PANEL_DOMAIN}->${web_backend},reality:${REALITY_SNI}->${xray_backend},default->${xray_backend}"
    fi
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] && summary+=",site:${domain}->${web_backend}"
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] && summary+=",tcp:${domain}->$(format_hostport "${TCP_ROUTE_ADDRS[$i]}" "${TCP_ROUTE_PORTS[$i]}")"
    done
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] && summary+=",xray:${domain}->$(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}")"
    done
    printf '%s' "$summary"
}

sni_stack_whitelist_summary_for_state() {
    local summary="" i
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        [[ -n "${SNI_IP_WHITELIST_DOMAINS[$i]}" && -n "${SNI_IP_WHITELIST_RANGES[$i]}" ]] || continue
        [[ -n "$summary" ]] && summary+="|"
        summary+="${SNI_IP_WHITELIST_DOMAINS[$i]}:${SNI_IP_WHITELIST_RANGES[$i]}"
    done
    printf '%s' "$summary"
}

write_single_443_engine_state() {
    local selected_engine="$1"
    local selected_engine_raw="$1"
    local backup_id="${2:-}"
    local state_file mux_config mux_service web_backend xray_backend routes whitelist_rules web_engine
    selected_engine=$(normalize_entry_mode_name "$selected_engine_raw") || { echo -e "${RED}Invalid engine: ${selected_engine_raw}${PLAIN}"; return 1; }
    state_file=$(single_443_engine_state_path)
    mux_config=$(vpso_mux_config_path)
    mux_service=$(vpso_mux_service_name)
    web_engine=$(current_web_proxy_engine)
    web_backend=$(web_proxy_backend)
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    routes=$(sni_stack_route_summary_for_state)
    whitelist_rules=$(sni_stack_whitelist_summary_for_state)
    [[ -z "$backup_id" ]] && backup_id=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null || true)

    mkdir -p /etc/vps-optimize
    cat <<EOF > "$state_file"
engine='${selected_engine}'
listen_addr='${NGINX_LISTEN_ADDR}'
listen_port='${NGINX_LISTEN_PORT}'
web_proxy_engine='${web_engine}'
web_proxy_backend='${web_backend}'
caddy_backend='${web_backend}'
xray_backend='${xray_backend}'
default_backend='${xray_backend}'
strict_sni_gate='$(normalize_strict_sni_gate "${STRICT_SNI_GATE:-false}")'
routes='${routes}'
whitelist_rules='${whitelist_rules}'
last_backup_id='${backup_id}'
mux_config_path='${mux_config}'
mux_systemd_service_name='${mux_service}'
EOF
    chmod 600 "$state_file" 2>/dev/null || true
}

show_single_443_engine_status() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔎 当前 443 入口状态 / 端口复用引擎${PLAIN}" "${BOLD}🔎 Current 443 entry status / Port 443 Reuse engine${PLAIN}" "${BOLD}🔎 Текущий статус записи 443 / система повторного использования порта 443${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    local engine state_file mux_config
    engine=$(single_443_current_engine)
    state_file=$(single_443_engine_state_path)
    mux_config=$(vpso_mux_config_path)
    show_current_entry_status
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "当前 engine：${GREEN}${engine}${PLAIN}" "Current engine: ${GREEN}${engine}${PLAIN}" "Текущий двигатель: ${GREEN}${engine}${PLAIN}.")"
    echo -e "$(localized_text "状态文件：${state_file}" "Status file: ${state_file}" "Файл состояния: ${state_file}")"
    echo -e "$(localized_text "mux 配置：${mux_config}" "mux configuration: ${mux_config}" "конфигурация мультиплексора: ${mux_config}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${GREEN}Nginx Stream 模式是默认稳定模式。${PLAIN}" "${GREEN}Nginx Stream mode is the default stable mode.${PLAIN}" "${GREEN}Режим Nginx Stream является стабильным режимом по умолчанию.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}TCP Peek + Splice 模式适合需要四层 SNI 分流和 splice 转发优化的进阶用户。${PLAIN}" "${YELLOW}TCP Peek + Splice mode Suitable for advanced users who require four-layer SNI offloading and splice forwarding optimization.${PLAIN}" "${YELLOW}Режим TCP Peek + Splice подходит для опытных пользователей, которым требуется четырехуровневая разгрузка SNI и оптимизация пересылки соединений.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}首次建议先监听 8444 测试，不要直接接管 443。${PLAIN}" "${YELLOW}For the first time, recommends listening to 8444 for testing instead of taking over 443 directly.${PLAIN}" "${YELLOW}Впервые рекомендует прослушивать 8444 для тестирования вместо непосредственного использования 443.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}切换前会自动备份，可回滚。${PLAIN}" "${YELLOW}Will automatically back up before switching and can be rolled back.${PLAIN}" "${YELLOW}автоматически создаст резервную копию перед переключением, и ее можно будет откатить.${PLAIN}")"
    echo -e "------------------------------------------------"
    if [[ -f /etc/vps-optimize/sni-stack.env ]]; then
        load_sni_stack_env >/dev/null 2>&1 && print_sni_stack_current_summary
    else
        echo -e "$(localized_text "${YELLOW}未检测到 sni-stack.env，尚未完成 443端口复用初始化。${PLAIN}" "${YELLOW}Did not detect sni-stack.env, and the Port 443 Reuse initialization has not been completed.${PLAIN}" "${YELLOW}не обнаружил sni-stack.env, и инициализация повторного использования порта 443 не завершена.${PLAIN}")"
    fi
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "公网 443 监听：" "public port 443 listening:" "прослушивание публичной сети 443:")"
    ss -lntup 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || echo "$(localized_text "未监听或当前用户无权限查看进程" "Not listening or the current user does not have permission to view the process" "Не прослушивается или текущий пользователь не имеет разрешения на просмотр процесса")"
}

show_tcp_peek_splice_info() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}TCP Peek + Splice 模式${PLAIN}" "${BOLD}TCP Peek + Splice mode${PLAIN}" "${BOLD}TCP Peek + Splice режим${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}TCP Peek + Splice 模式：基于 MSG_PEEK 读取 TLS ClientHello 中的 SNI，不消费首包，并根据 SNI 将连接分流到 Caddy 或 Xray 本地后端；转发时优先使用 splice 零拷贝，失败时自动回退普通 copy。实际运行的分流器程序为 vpso-mux。${PLAIN}" "${YELLOW}TCP Peek + Splice mode: Read SNI in TLS ClientHello based on MSG_PEEK, do not consume the first packet, and routing the connection to the Caddy or Xray local backend based on SNI; use splice first when forwarding Zero copy, automatic fallback to normal copy when failure occurs. The actual running routing program is vpso-mux.${PLAIN}" "${YELLOW}Режим TCP Peek + Splice: читайте SNI в TLS ClientHello на основе MSG_PEEK, не потребляйте первый пакет и маршрутизируйте соединение с локальным сервером Caddy или Xray на основе SNI; сначала используйте сращивание при пересылке нулевой копии, автоматический возврат к обычной копии в случае сбоя. Действующая программа маршрутизирования — vpso-mux.${PLAIN}")"
    echo -e "$(localized_text "它只在 TCP 层读取 TLS ClientHello 的 SNI，不终止 TLS，不管理证书，不替换 Caddy，也不是 Xray 直占 443。" "It only reads SNI of TLS ClientHello at the TCP layer, does not terminate TLS, does not manage certificates, does not replace Caddy, and is not directly occupied by Xray 443." "Он читает только SNI из TLS ClientHello на уровне TCP, не завершает TLS, не управляет сертификатами, не заменяет Caddy и не занят непосредственно Xray 443.")"
    echo -e "$(localized_text "推荐流程：" "Recommended process:" "Рекомендуемый процесс:")"
    echo -e "$(localized_text "  1. 先生成 TCP Peek + Splice 分流规则：/etc/vps-optimize/vpso-mux.yaml" "1. First generate the TCP Peek + Splice routing rule: /etc/vps-optimize/vpso-mux.yaml" "1. Сначала создайте правило маршрутизации TCP Peek + Splice: /etc/vps-optimize/vpso-mux.yaml.")"
    echo -e "$(localized_text "  2. 校验配置和后端端口" "2. Verify configuration and backend port" "2. Проверьте конфигурацию и внутренний порт.")"
    echo -e "$(localized_text "  3. 使用 TCP Peek + Splice 测试入口监听 8444" "3. Use TCP Peek + Splice to test entry listening 8444" "3. Используйте TCP Peek + Splice для проверки системы контроля входа 8444.")"
    echo -e "$(localized_text "  4. 确认后再事务式切换公网 443" "4. After confirmation, switch to the public transactionally 443" "4. После подтверждения переключитесь в публичную сеть транзакционно 443.")"
    echo -e "$(localized_text "  5. 异常时从菜单回滚到 Nginx Stream 模式" "5. Roll back to Nginx Stream mode from the menu in case of exception" "5. Откатиться в режим Nginx Stream из меню в случае исключения")"
}

print_vpso_mux_systemd_fallback_status() {
    local listen_port="${1:-${NGINX_LISTEN_PORT:-443}}"
    local public_lines preflight_lines
    echo -e "$(localized_text "${YELLOW}status.json 不存在或解析失败，已降级为 systemd / 监听状态检查。${PLAIN}" "${YELLOW}Status.json does not exist or fails to parse, and has been downgraded to systemd/listening status check.${PLAIN}" "${YELLOW}status.json не существует или его не удалось проанализировать, и его ранг был понижен до systemd/проверка статуса прослушивания.${PLAIN}")"
    echo -e "vpso-mux：$(service_status_compact vpso-mux)"
    echo -e "vpso-mux-preflight：$(service_status_compact vpso-mux-preflight)"
    echo -e "$(localized_text "公网 ${listen_port} 监听：" "public ${listen_port} listening:" "прослушивание публичной сети ${listen_port}:")"
    public_lines=$(ss -lntp 2>/dev/null | awk -v p=":${listen_port}" '$4 ~ p"$" {print}' || true)
    echo "$(localized_text "${public_lines:-未监听或当前用户无权限查看进程}" "${public_lines:-未监听或当前用户无权限查看进程}" "${public_lines:-未监听或当前用户无权限查看进程}")"
    echo -e "$(localized_text "8444 预检监听：" "8444 Preflight listening:" "8444 Предполетный контроль:")"
    preflight_lines=$(ss -lntp 2>/dev/null | awk '$4 ~ ":8444$" {print}' || true)
    echo "$(localized_text "${preflight_lines:-未监听或当前用户无权限查看进程}" "${preflight_lines:-未监听或当前用户无权限查看进程}" "${preflight_lines:-未监听或当前用户无权限查看进程}")"
}

print_vpso_mux_status_json() {
    local status_file py_bin
    status_file=$(vpso_mux_status_json_path)
    [[ -s "$status_file" ]] || return 1

    if command -v python3 >/dev/null 2>&1; then
        py_bin="python3"
    elif command -v python >/dev/null 2>&1; then
        py_bin="python"
    else
        return 1
    fi

    "$py_bin" - "$status_file" "$VPSO_LANGUAGE" <<'PY'
import json
import sys

path = sys.argv[1]
language = sys.argv[2] if len(sys.argv) > 2 else "zh"
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

def value(name, default=0):
    return data.get(name, default)

labels = {
    "zh": {
        "started": "启动时间", "updated": "更新时间", "listen": "监听地址",
        "max": "连接上限", "active": "当前连接数", "total": "连接总数",
        "rejected": "拒绝连接数", "dial_errors": "后端拨号错误",
        "retry_attempts": "后端重试尝试", "retry_success": "后端重试成功",
        "retry_failed": "后端重试失败", "splice": "splice 成功次数",
        "fallback": "copy fallback 次数", "blocked": "白名单拦截次数", "unknown_blocked": "严格 SNI 门禁拦截次数",
        "no_sni": "no_sni 次数", "peek_errors": "peek 错误次数",
        "peek_timeouts": "peek 超时次数", "up": "客户端->后端字节",
        "down": "后端->客户端字节", "routes": "按 route 命中次数 Top 10",
        "errors": "最近错误", "none": "暂无",
    },
    "en": {
        "started": "Started", "updated": "Updated", "listen": "Listen addresses",
        "max": "Connection limit", "active": "Active connections", "total": "Total connections",
        "rejected": "Rejected connections", "dial_errors": "Backend dial errors",
        "retry_attempts": "Backend retry attempts", "retry_success": "Successful backend retries",
        "retry_failed": "Failed backend retries", "splice": "Successful splice operations",
        "fallback": "copy fallback operations", "blocked": "Whitelist blocks", "unknown_blocked": "Strict SNI gate blocks",
        "no_sni": "no_sni connections", "peek_errors": "peek errors",
        "peek_timeouts": "peek timeouts", "up": "Client-to-backend bytes",
        "down": "Backend-to-client bytes", "routes": "Top 10 route hits",
        "errors": "Recent errors", "none": "None",
    },
    "ru": {
        "started": "Время запуска", "updated": "Время обновления", "listen": "Адреса прослушивания",
        "max": "Лимит подключений", "active": "Активные подключения", "total": "Всего подключений",
        "rejected": "Отклонённые подключения", "dial_errors": "Ошибки подключения к бэкенду",
        "retry_attempts": "Попытки повтора подключения", "retry_success": "Успешные повторы подключения",
        "retry_failed": "Неудачные повторы подключения", "splice": "Успешные операции splice",
        "fallback": "Операции copy fallback", "blocked": "Блокировки белым списком", "unknown_blocked": "Блокировки строгим контролем SNI",
        "no_sni": "Подключения no_sni", "peek_errors": "Ошибки peek",
        "peek_timeouts": "Тайм-ауты peek", "up": "Байты от клиента к бэкенду",
        "down": "Байты от бэкенда к клиенту", "routes": "10 самых частых маршрутов",
        "errors": "Последние ошибки", "none": "Нет",
    },
}
text = labels.get(language, labels["zh"])

print(f"status.json：{path}")
print(f"{text['started']}: {value('start_time', 'unknown')}")
print(f"{text['updated']}: {value('updated_at', 'unknown')}")
listen = data.get("listen_addresses") or []
print(f"{text['listen']}: " + (", ".join(listen) if listen else "unknown"))
max_connections = value('max_connections', 'unlimited')
if max_connections == 0:
    max_connections = 'unlimited'
print(f"{text['max']}: {max_connections}")
print(f"{text['active']}: {value('active_connections')}")
print(f"{text['total']}: {value('total_connections')}")
print(f"{text['rejected']}: {value('rejected_connections')}")
print(f"{text['dial_errors']}: {value('backend_dial_errors')}")
print(f"{text['retry_attempts']}: {value('backend_retry_attempts')}")
print(f"{text['retry_success']}: {value('backend_retry_success')}")
print(f"{text['retry_failed']}: {value('backend_retry_failed')}")
print(f"{text['splice']}: {value('splice_success')}")
print(f"{text['fallback']}: {value('copy_fallback')}")
print(f"{text['blocked']}: {value('whitelist_blocked')}")
print(f"{text['unknown_blocked']}: {value('unknown_sni_blocked')}")
print(f"{text['no_sni']}: {value('no_sni')}")
print(f"{text['peek_errors']}: {value('peek_errors')}")
print(f"{text['peek_timeouts']}: {value('peek_timeouts')}")
print(f"{text['up']}: {value('bytes_client_to_backend')}")
print(f"{text['down']}: {value('bytes_backend_to_client')}")

route_hits = data.get("route_hits") or {}
print(f"{text['routes']}:")
if route_hits:
    for name, count in sorted(route_hits.items(), key=lambda item: (-int(item[1]), item[0]))[:10]:
        print(f"  - {name}: {count}")
else:
    print(f"  - {text['none']}")

recent_errors = data.get("recent_errors") or []
print(f"{text['errors']}:")
if recent_errors:
    for item in recent_errors[-10:]:
        at = item.get("time", "unknown")
        msg = item.get("message", "")
        route = item.get("route_name", "")
        sni = item.get("sni", "")
        suffix = ""
        if route:
            suffix += f" route={route}"
        if sni:
            suffix += f" sni={sni}"
        print(f"  - {at} {msg}{suffix}")
else:
    print(f"  - {text['none']}")
PY
}

show_vpso_mux_runtime_status() {
    local status_file
    status_file=$(vpso_mux_status_json_path)
    echo -e "$(localized_text "${BOLD}TCP Peek + Splice 运行统计${PLAIN}" "${BOLD}TCP Peek + Splice Operation statistics${PLAIN}" "${BOLD}TCP Peek + Splice Статистика работы${PLAIN}")"
    if ! print_vpso_mux_status_json; then
        print_vpso_mux_systemd_fallback_status "${NGINX_LISTEN_PORT:-443}"
    fi
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "配置文件：$(vpso_mux_config_path)" "Configuration file: $(vpso_mux_config_path)" "Файл конфигурации: $(vpso_mux_config_path).")"
    echo -e "systemd：/etc/systemd/system/$(vpso_mux_service_name)"
    echo -e "$(localized_text "状态文件：${status_file}" "Status file: ${status_file}" "Файл состояния: ${status_file}")"
}
