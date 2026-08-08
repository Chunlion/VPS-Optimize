# shellcheck shell=bash
# TCP Peek preflight, entry-mode cutover, and runtime actions.

vpso_mux_preflight_config_path() {
    echo "/etc/vps-optimize/vpso-mux.preflight.yaml"
}

write_vpso_mux_preflight_service() {
    cat <<'EOF' > /etc/systemd/system/vpso-mux-preflight.service
[Unit]
Description=VPS-Optimize TCP Peek preflight router on 8444
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vpso-mux -config /etc/vps-optimize/vpso-mux.preflight.yaml
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 /etc/systemd/system/vpso-mux-preflight.service
    systemctl daemon-reload >/dev/null 2>&1 || true
}

port_listener_has_process() {
    local port="$1"
    local proc_pattern="$2"
    ss -lntp 2>/dev/null | grep -E "(:${port}[[:space:]]|:${port}$)" | grep -q "$proc_pattern"
}

tcppeek_preflight_probe_route_matrix() {
    local test_port="$1"
    local connect_host domain i route_addr route_port failures=0
    connect_host=$(probe_host_for_listen_addr "$NGINX_LISTEN_ADDR")

    echo -e "$(localized_text "${CYAN}▶ 检查 TCP Peek 8444 路由矩阵...${PLAIN}" "${CYAN}▶ Check TCP Peek 8444 routing matrix...${PLAIN}" "${CYAN}▶ Проверьте матрицу маршрутизации TCP Peek 8444...${PLAIN}")"
    probe_tls_sni_certificate "$(localized_text "TCP Peek 8444 面板 SNI 预检" "TCP Peek 8444 panel SNI preflight check" "TCP Peek 8444 панель SNI предварительная проверка")" "$connect_host" "$test_port" "$PANEL_DOMAIN" || failures=1

    for domain in "${SITE_DOMAINS[@]}"; do
        [[ -n "$domain" ]] || continue
        probe_tls_sni_certificate "$(localized_text "TCP Peek 8444 Web SNI 预检 ${domain}" "TCP Peek 8444 Web SNI preflight check ${domain}" "TCP Peek 8444 Интернет SNI Предварительная проверка ${domain}")" "$connect_host" "$test_port" "$domain" || failures=1
    done

    tcp_probe_host "$(localized_text "TCP Peek 默认 Xray/REALITY 后端" "TCP Peek Default Xray/REALITY backend" "TCP Peek бэкенд по умолчанию Xray/REALITY")" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 3 1 || failures=1

    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        route_addr="${TCP_ROUTE_ADDRS[$i]}"
        route_port="${TCP_ROUTE_PORTS[$i]}"
        [[ -n "$domain" && -n "$route_addr" && -n "$route_port" ]] || continue
        tcp_probe_host "$(localized_text "TCP Peek 本地 TCP/SNI 后端 ${domain}" "TCP Peek local TCP/SNI backend ${domain}" "TCP Peek локальный TCP/SNI бэкенд ${domain}")" "$(probe_host_for_listen_addr "$route_addr")" "$route_port" 3 1 || failures=1
    done

    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        route_addr="${XRAY_SNI_ROUTE_ADDRS[$i]}"
        route_port="${XRAY_SNI_ROUTE_PORTS[$i]}"
        [[ -n "$domain" && -n "$route_addr" && -n "$route_port" ]] || continue
        tcp_probe_host "$(localized_text "TCP Peek Xray SNI 后端 ${domain}" "TCP Peek Xray SNI Backend ${domain}" "TCP Peek Xray SNI бэкенд ${domain}")" "$(probe_host_for_listen_addr "$route_addr")" "$route_port" 3 1 || failures=1
    done

    if [[ "$failures" -ne 0 ]]; then
        echo -e "$(localized_text "${RED}❌ TCP Peek 8444 路由矩阵预检失败，公网 443 未改动。${PLAIN}" "${RED}❌ TCP Peek 8444 Routing matrix preflight check failed, public port 443 has not been changed.${PLAIN}" "${RED}❌ TCP Peek 8444 Предварительная проверка матрицы маршрутизации не удалась, публичный порт 443 не был изменён.${PLAIN}")"
        return 1
    fi
    echo -e "$(localized_text "${GREEN}✅ TCP Peek 8444 路由矩阵预检通过。${PLAIN}" "${GREEN}✅ TCP Peek 8444 Routing matrix preflight check passed.${PLAIN}" "${GREEN}✅ TCP Peek 8444 Предварительная проверка матрицы маршрутизации пройдена.${PLAIN}")"
    return 0
}

run_tcppeek_preflight_service() {
    local keep_running="${1:-0}"
    local test_port="${2:-8444}"
    local config_file tmp_config
    config_file=$(vpso_mux_preflight_config_path)

    require_vpso_mux_binary_for_cutover || return 1
    tmp_config="${config_file}.tmp.$$"
    write_vpso_mux_config_from_sni_stack "$test_port" "$tmp_config" || return 1
    if ! run_vpso_mux_config_check "$tmp_config"; then
        quarantine_path "$tmp_config" "/etc/vps-optimize/quarantine/vpso-mux" >/dev/null 2>&1 || true
        return 1
    fi
    mv "$tmp_config" "$config_file" || return 1
    write_vpso_mux_preflight_service
    systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
    if ! systemctl start vpso-mux-preflight; then
        echo -e "$(localized_text "${RED}❌ TCP Peek 8444 预检服务启动失败，公网 443 未改动。${PLAIN}" "${RED}❌ TCP Peek 8444 The preflight service failed to start, and the public port 443 has not been changed.${PLAIN}" "${RED}❌ TCP Peek 8444 Не удалось запустить предполетную службу, а публичный порт 443 не был изменён.${PLAIN}")"
        return 1
    fi
    sleep 1
    if ! port_listener_has_process "$test_port" 'vpso-mux'; then
        systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
        echo -e "$(localized_text "${RED}❌ TCP Peek 8444 预检未监听到 vpso-mux，拒绝切换公网 443。${PLAIN}" "${RED}❌ TCP Peek 8444 The precheck did not detect vpso-mux and refused to switch to the public port 443.${PLAIN}" "${RED}❌ TCP Peek 8444 Предварительная проверка не обнаружила vpso-mux и отказалась переключаться в публичную сеть 443.${PLAIN}")"
        return 1
    fi
    tcppeek_preflight_probe_route_matrix "$test_port" || {
        systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
        return 1
    }
    if [[ "$keep_running" != "1" ]]; then
        systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
    fi
    return 0
}

tcp_peek_dry_run_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}TCP Peek + Splice 分流规则校验${PLAIN}" "${BOLD}TCP Peek + Splice Routing rule verification${PLAIN}" "${BOLD}TCP Peek + Splice Проверка правил маршрутизации${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    local config_file
    config_file=$(vpso_mux_config_path)
    [[ -f "$config_file" ]] || { echo -e "$(localized_text "${YELLOW}未找到 ${config_file}，正在先生成配置。${PLAIN}" "${YELLOW}${config_file} was not found; generating it first.${PLAIN}" "${YELLOW}Файл ${config_file} не найден; сначала создаётся конфигурация.${PLAIN}")"; write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$config_file" || return 1; }
    echo -e "$(localized_text "${CYAN}▶ 校验 YAML、SNI、backend、whitelist 和重复 SNI...${PLAIN}" "${CYAN}▶ Check YAML, SNI, backend, whitelist and duplicate SNI...${PLAIN}" "${CYAN}▶ Проверьте YAML, SNI, бэкенд, белый список и дубликат SNI....${PLAIN}")"
    run_vpso_mux_config_check "$config_file" || return 1
    echo -e "$(localized_text "${CYAN}▶ 检查本地后端端口...${PLAIN}" "${CYAN}▶ Check local backend port...${PLAIN}" "${CYAN}▶ Проверьте локальный внутренний порт...${PLAIN}")"
    tcp_probe_host "Caddy 127.0.0.1:${CADDY_LISTEN_PORT}" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || true
    tcp_probe_host "Xray/REALITY 127.0.0.1:${XRAY_LISTEN_PORT}" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" || true
    print_sni_ip_whitelist_summary
    echo -e "$(localized_text "${GREEN}✅ 配置校验完成。请先使用 TCP Peek + Splice 测试入口验证，不要直接接管 443。${PLAIN}" "${GREEN}✅ configuration validation completed. Please use TCP Peek + Splice test entry verification first, do not take over 443 directly.${PLAIN}" "${GREEN}✅ Проверка конфигурации завершена. Пожалуйста, сначала используйте тестовую проверку входа TCP Peek + Splice, не переключайте публичный порт 443 напрямую.${PLAIN}")"
}

start_tcp_peek_test_port() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}TCP Peek + Splice 状态 / 测试入口${PLAIN}" "${BOLD}TCP Peek + Splice status / test entry${PLAIN}" "${BOLD}TCP Peek + Splice статус/тестовый вход${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    if ! load_sni_stack_env; then
        NGINX_LISTEN_PORT="${NGINX_LISTEN_PORT:-443}"
        show_vpso_mux_runtime_status
        return 1
    fi
    show_vpso_mux_runtime_status
    echo -e "------------------------------------------------"
    if [[ "$(single_443_current_engine)" == "tcp-peek" ]]; then
        echo -e "$(localized_text "${YELLOW}当前入口已经是 TCP Peek + Splice 模式。为避免误停公网 443，本入口不覆盖运行中的 443 配置。${PLAIN}" "${YELLOW}The current entry of is already in TCP Peek + Splice mode. To avoid accidentally stopping the public port 443, this entry does not cover the running 443 configuration.${PLAIN}" "${YELLOW}Текущая запись уже находится в режиме TCP Peek + Splice. Чтобы избежать случайной остановки публичного порта 443, эта запись не распространяется на работающую конфигурацию 443.${PLAIN}")"
        return 0
    fi
    echo -e "$(localized_text "${YELLOW}vpso-mux 预检服务只监听 8444，当前公网 443 入口不会被停止或替换。${PLAIN}" "${YELLOW}Vpso-mux The preflight service only listens to 8444, and the current public port 443 entry will not be stopped or replaced.${PLAIN}" "${YELLOW}vpso-mux Предполетная служба слушает только 8444, и текущий вход в публичный порт 443 не будет остановлен или заменен.${PLAIN}")"
    confirm_risk_action "$(localized_text "安装/构建 vpso-mux 并启动 8444 预检" "Install/build vpso-mux and start 8444 preflight" "Установите/соберите vpso-mux и запустите предварительная проверка 8444.")" \
        "$(localized_text "可能安装 Go 工具链、构建 /usr/local/bin/vpso-mux，并启动独立 vpso-mux-preflight.service 监听 8444" "Possibly install the Go toolchain, build /usr/local/bin/vpso-mux, and start the standalone vpso-mux-preflight.service listener 8444" "Возможно, установите набор инструментов Go, соберите /usr/local/bin/vpso-mux и запустите автономный прослушиватель vpso-mux-preflight.service 8444.")" \
        "$(localized_text "停止 vpso-mux-preflight.service，或继续使用 Nginx Stream / Xray Fallback，不会改动公网 443" "Stop vpso-mux-preflight.service, or continue to use Nginx Stream / Xray Fallback, which will not change the public port 443" "Остановите vpso-mux-preflight.service или продолжайте использовать Nginx Stream/Xray Fallback, который не изменит публичную сеть 443")" \
        "$(localized_text "低内存或低磁盘机器会被资源预检查拦截；公网 443 在本步骤不会被替换。" "Low memory or low disk machines will be blocked by resource preflight check; public port 443 will not be replaced in this step." "Машины с нехваткой памяти или диска будут заблокированы предварительной проверкой ресурсов; публичный порт 443 не будет заменена на этом этапе.")" || return 1
    install_vpso_mux_binary || return 1
    apply_web_proxy_configs_for_single_443 || return 1
    restart_web_proxy_for_single_443 || return 1
    tcp_probe_host "$(localized_text "$(web_proxy_engine_label) 本地 TLS" "$(web_proxy_engine_label) local TLS" "$(web_proxy_engine_label) локальный TLS")" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    tcp_probe_host "$(localized_text "Xray/REALITY 本地入站" "Xray/REALITY local inbound" "Xray/REALITY локальное входящее подключение")" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1 || return 1
    run_tcppeek_preflight_service 1 "8444" || return 1
    echo -e "$(localized_text "${GREEN}✅ vpso-mux 预检服务已启动在测试端口 8444，公网 443 未改动。${PLAIN}" "${GREEN}✅ vpso-mux preflight service has been started on test port 8444, and public port 443 has not been changed.${PLAIN}" "${GREEN}✅ Служба предварительной проверки vpso-mux запущена на тестовом порту 8444, а публичный порт 443 не был изменён.${PLAIN}")"
    echo -e "$(localized_text "测试命令：" "Test command:" "Тестовая команда:")"
    echo -e "  openssl s_client -connect SERVER_IP:8444 -servername ${PANEL_DOMAIN}"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  openssl s_client -connect SERVER_IP:8444 -servername ${SITE_DOMAINS[0]}"
    echo -e "  openssl s_client -connect SERVER_IP:8444 -servername random.example.com"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  curl -vk --resolve ${SITE_DOMAINS[0]}:8444:SERVER_IP https://${SITE_DOMAINS[0]}:8444/"
}

preflight_tcppeek_before_cutover() {
    echo -e "$(localized_text "${CYAN}▶ 正在执行 TCP Peek 8444 安全预检，公网 443 暂不改动...${PLAIN}" "${CYAN}▶ Executing TCP Peek 8444 security preflight check, public port 443 No changes for now...${PLAIN}" "${CYAN}▶ Выполнение предварительной проверки безопасности TCP Peek 8444, публичный порт 443 На данный момент изменений нет...${PLAIN}")"
    require_vpso_mux_binary_for_cutover || return 1
    warn_if_public_bind "$(web_proxy_engine_label)" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    apply_web_proxy_configs_for_single_443 || return 1
    restart_web_proxy_for_single_443 || return 1
    tcp_probe_host "$(localized_text "$(web_proxy_engine_label) 本地 TLS" "$(web_proxy_engine_label) local TLS" "$(web_proxy_engine_label) локальный TLS")" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    tcp_probe_host "$(localized_text "Xray/REALITY 本地入站" "Xray/REALITY local inbound" "Xray/REALITY локальное входящее подключение")" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1 || {
        echo -e "$(localized_text "${RED}❌ Xray 本地入站不可达，拒绝切换 TCP Peek。请先在 3x-ui/Xray 中准备本地监听入站。${PLAIN}" "${RED}❌ Xray The local inbound is unreachable and the switch to TCP Peek is refused. Please prepare local listeners inbound in 3x-ui/Xray first.${PLAIN}" "${RED}❌ Xray локальное входящее подключение недоступно, и в переключении на TCP Peek отказано. Пожалуйста, сначала подготовьте локальное входящее подключение в 3x-ui/Xray.${PLAIN}")"
        return 1
    }
    run_tcppeek_preflight_service 0 "8444" || return 1
    echo -e "$(localized_text "${GREEN}✅ TCP Peek 8444 预检通过，才会进入公网 443 切换。${PLAIN}" "${GREEN}✅ TCP Peek 8444 Only after passing the preflight check will it enter the public port 443 switch.${PLAIN}" "${GREEN}✅ TCP Peek 8444 Только после прохождения предварительной проверки он попадет в коммутатор публичной сети 443.${PLAIN}")"
}

preflight_entry_mode_before_cutover() {
    local target_mode="$1"
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1
    case "$target_mode" in
        "tcp-peek") preflight_tcppeek_before_cutover ;;
        *) return 0 ;;
    esac
}

normalize_entry_mode_name() {
    local mode="$1"
    case "$mode" in
        "nginx_stream"|"nginx-stream") echo "nginx-stream" ;;
        "xray_fallback"|"xray-fallback") echo "xray-fallback" ;;
        "tcp_peek"|"tcp-peek") echo "tcp-peek" ;;
        *) return 1 ;;
    esac
}

entry_mode_engine_name() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode") || return 1
    echo "$mode"
}

print_entry_mode_cutover_paths() {
    local target_mode="$1"
    echo -e "$(localized_text "${BOLD}将涉及的配置路径${PLAIN}" "${BOLD}Will involve the configuration path${PLAIN}" "${BOLD}будет включать путь конфигурации.${PLAIN}")"
    echo -e "Nginx：/etc/nginx/nginx.conf"
    echo -e "Nginx：/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf"
    echo -e "Nginx：/etc/nginx/conf.d/00-vps-default-drop.conf"
    echo -e "Caddy：/etc/caddy/Caddyfile"
    echo -e "Caddy：/etc/caddy/conf.d/${PANEL_DOMAIN}.caddy"
    local site_domain
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ -n "$site_domain" ]] && echo -e "Caddy：/etc/caddy/conf.d/${site_domain}.caddy"
    done
    echo -e "systemd：/etc/systemd/system/vpso-mux.service"
    echo -e "vpso-mux：$(vpso_mux_config_path)"
    echo -e "$(localized_text "状态：$(single_443_engine_state_path)" "Status: $(single_443_engine_state_path)" "Статус: $(single_443_engine_state_path)")"
    echo -e "$(localized_text "共享参数：/etc/vps-optimize/sni-stack.env" "Shared parameters: /etc/vps-optimize/sni-stack.env" "Общие параметры: /etc/vps-optimize/sni-stack.env")"
    if [[ "$target_mode" == "tcp-peek" ]]; then
        echo -e "$(localized_text "vpso-mux 状态：$(vpso_mux_status_json_path)" "vpso-mux Status: $(vpso_mux_status_json_path)" "Статус vpso-mux: $(vpso_mux_status_json_path)")"
    fi
}

print_preview_file_diff() {
    local actual_path="$1"
    local planned_path="$2"
    local title="$3"

    echo -e "${CYAN}--- ${title}${PLAIN}"
    if ! command -v diff >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}未检测到 diff 命令，无法显示文本差异。${PLAIN}" "${YELLOW}The diff command was not detected and text differences cannot be displayed.${PLAIN}" "${YELLOW}Команда diff не обнаружена, и текстовые различия не могут быть отображены.${PLAIN}")"
        return 0
    fi

    if [[ -f "$actual_path" && -f "$planned_path" ]]; then
        diff -u --label "$(localized_text "${actual_path} (当前)" "${actual_path} (current)" "${actual_path} (текущий)")" --label "$(localized_text "${actual_path} (预计)" "${actual_path} (estimated)" "${actual_path} (оценка)")" "$actual_path" "$planned_path" || true
    elif [[ -f "$actual_path" && ! -f "$planned_path" ]]; then
        diff -u --label "$(localized_text "${actual_path} (当前)" "${actual_path} (current)" "${actual_path} (текущий)")" --label "$(localized_text "${actual_path} (预计停用)" "${actual_path} (expected to be discontinued)" "${actual_path} (скорее всего, будет снят с производства)")" "$actual_path" /dev/null || true
    elif [[ ! -f "$actual_path" && -f "$planned_path" ]]; then
        diff -u --label "$(localized_text "${actual_path} (当前不存在)" "${actual_path} (does not currently exist)" "${actual_path} (в настоящее время не существует)")" --label "$(localized_text "${actual_path} (预计新增)" "${actual_path} (expected to be added)" "${actual_path} (ожидается добавление)")" /dev/null "$planned_path" || true
    else
        echo "$(localized_text "当前和预计都没有该文件。" "This file is neither currently nor expected to be available." "Этот файл в настоящее время недоступен и не ожидается, что он будет доступен.")"
    fi
    echo ""
}

write_entry_preview_caddyfile() {
    local output_file="$1"
    cat <<'EOF' > "$output_file"
{
    auto_https off
}

import conf.d/*
EOF
}

show_entry_mode_cutover_diff() {
    local target_mode="$1"
    local tmp_dir target_root target_caddy_dir target_nginx target_mux target_service target_caddyfile
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1
    tmp_dir=$(mktemp -d /tmp/vpso-entry-preview.XXXXXX) || return 1
    chmod 700 "$tmp_dir" 2>/dev/null || true
    target_root="${tmp_dir}/target"
    target_caddy_dir="${target_root}/etc/caddy/conf.d"
    mkdir -p "$target_caddy_dir" "${target_root}/etc/nginx/stream.d" "${target_root}/etc/vps-optimize" "${target_root}/etc/systemd/system"

    target_caddyfile="${target_root}/etc/caddy/Caddyfile"
    target_nginx="${target_root}/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf"
    target_mux="${target_root}/etc/vps-optimize/vpso-mux.yaml"
    target_service="${target_root}/etc/systemd/system/vpso-mux.service"

    write_entry_preview_caddyfile "$target_caddyfile"
    write_caddy_panel_config "${target_caddy_dir}/${PANEL_DOMAIN}.caddy"
    write_caddy_site_config "$target_caddy_dir"

    if [[ "$target_mode" == "nginx-stream" ]]; then
        write_nginx_sni_stream_config "$target_nginx" "no"
    fi
    if [[ "$target_mode" == "tcp-peek" ]]; then
        write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$target_mux"
        write_vpso_mux_systemd_service "$target_service"
    else
        [[ -f "$(vpso_mux_config_path)" ]] && cp -a "$(vpso_mux_config_path)" "$target_mux" 2>/dev/null || true
        [[ -f /etc/systemd/system/vpso-mux.service ]] && cp -a /etc/systemd/system/vpso-mux.service "$target_service" 2>/dev/null || true
    fi

    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}443 单入口切换 diff 预览${PLAIN}" "${BOLD}443 Shared entry switch diff preview${PLAIN}" "${BOLD}443 Предварительный просмотр дифференциала переключения одной записи${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    print_preview_file_diff "/etc/caddy/Caddyfile" "$target_caddyfile" "Caddyfile"
    print_preview_file_diff "/etc/caddy/conf.d/${PANEL_DOMAIN}.caddy" "${target_caddy_dir}/${PANEL_DOMAIN}.caddy" "$(localized_text "Caddy 面板域名" "Caddy panel domain" "Доменное имя панели Caddy")"
    local site_domain
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ -n "$site_domain" ]] || continue
        print_preview_file_diff "/etc/caddy/conf.d/${site_domain}.caddy" "${target_caddy_dir}/${site_domain}.caddy" "$(localized_text "Caddy 网站/反代 ${site_domain}" "Caddy website/reverse proxy ${site_domain}" "Caddy веб-сайт/обратный прокси ${site_domain}")"
    done
    print_preview_file_diff "/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf" "$target_nginx" "$(localized_text "Nginx Stream 入口" "Nginx Stream entry" "Nginx Stream вход")"
    print_preview_file_diff "$(vpso_mux_config_path)" "$target_mux" "$(localized_text "vpso-mux 分流配置" "vpso-mux routing configuration" "Конфигурация маршрутизации vpso-mux")"
    print_preview_file_diff "/etc/systemd/system/vpso-mux.service" "$target_service" "vpso-mux systemd"
    echo -e "$(localized_text "${YELLOW}diff 预览只在临时目录生成目标文件，不会写入 /etc。临时目录：${tmp_dir}${PLAIN}" "${YELLOW}Diff preview only generates target files in the temporary directory and will not write to /etc. Temporary directory: ${tmp_dir}${PLAIN}" "${YELLOW}Предварительный просмотр diff создает целевые файлы только во временном каталоге и не записывает их в /etc. Временный каталог: ${tmp_dir}.${PLAIN}")"
}

preview_entry_mode_cutover() {
    local current_mode="$1"
    local target_mode="$2"
    local backup_dir="$3"
    local listener_info current_listener current_display expected_listener expected_display choice

    current_mode=$(normalize_entry_mode_name "$current_mode" 2>/dev/null || echo "$current_mode")
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1
    listener_info=$(detect_443_listener "$NGINX_LISTEN_PORT")
    current_listener="${listener_info%%|*}"
    current_display=$(entry_listener_display_name "$current_listener")
    expected_listener=$(entry_mode_expected_listener "$target_mode") || return 1
    expected_display=$(entry_listener_display_name "$expected_listener")

    while true; do
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}443 单入口切换变更预览${PLAIN}" "${BOLD}443 shared entry switching change preview${PLAIN}" "${BOLD}443 Предварительный просмотр изменений коммутации на один вход${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "当前 ENTRY_MODE：${current_mode}" "Current ENTRY_MODE: ${current_mode}" "Текущий ENTRY_MODE: ${current_mode}")"
        echo -e "$(localized_text "目标 ENTRY_MODE：${target_mode}" "Target ENTRY_MODE: ${target_mode}" "Цель ENTRY_MODE: ${target_mode}")"
        echo -e "$(localized_text "当前 443 监听者：${current_display} (${listener_info#*|})" "Current 443 listener: ${current_display} (${listener_info#*|})" "Текущий прослушиватель 443: ${current_display} (${listener_info#*|})")"
        echo -e "$(localized_text "切换后预计监听者：${expected_display}" "Expected listener after switching: ${expected_display}" "Ожидаемый слушатель после переключения: ${expected_display}")"
        echo -e "$(localized_text "回滚点位置：${backup_dir}" "Rollback point position: ${backup_dir}" "Позиция точки отката: ${backup_dir}")"
        echo -e "------------------------------------------------"
        print_entry_mode_cutover_paths "$target_mode"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 查看 diff${PLAIN}" "${GREEN}1. View diff${PLAIN}" "${GREEN}1. Посмотреть разницу${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 继续切换${PLAIN}" "${GREEN}2. Continue to switch to${PLAIN}" "${GREEN}2. Продолжайте переходить на.${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 取消，不修改任何配置${PLAIN}" "${RED}0. Cancel without modifying any configuration${PLAIN}" "${RED}0. Отмена без изменения конфигурации.${PLAIN}")"
        read_trimmed choice "$(localized_text "请选择操作（默认 0 取消）: " "Please select an action (default 0 cancels):" "Пожалуйста, выберите действие (по умолчанию 0 отменяет):")"
        case "$(echo "${choice:-0}" | tr '[:upper:]' '[:lower:]')" in
            1|d|D|diff)
                show_entry_mode_cutover_diff "$target_mode"
                ;;
            2|y|yes)
                return 0
                ;;
            0|n|no|q)
                echo -e "$(localized_text "${BLUE}已取消 443 入口切换，未修改任何配置。${PLAIN}" "${BLUE}Canceled the 443 entry switch without modifying any configuration.${PLAIN}" "${BLUE}отменил входной переключатель 443 без изменения какой-либо конфигурации.${PLAIN}")"
                return 1
                ;;
            *)
                echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"
                ;;
        esac
    done
}

systemd_unit_exists() {
    local unit="$1"
    systemctl list-unit-files "$unit" >/dev/null 2>&1 || systemctl status "$unit" >/dev/null 2>&1
}

xray_entry_service_name() {
    local svc
    for svc in xray.service x-ui.service 3x-ui.service; do
        if systemd_unit_exists "$svc"; then
            echo "${svc%.service}"
            return 0
        fi
    done
    return 1
}

restart_xray_entry_service() {
    local svc
    svc=$(xray_entry_service_name) || { echo -e "$(localized_text "${RED}❌ 未检测到 xray/x-ui/3x-ui systemd 服务。${PLAIN}" "${RED}❌ xray/x-ui/3x-ui systemd service not detected.${PLAIN}" "${RED}❌ xray/x-ui/3x-ui Служба systemd не обнаружена.${PLAIN}")"; return 1; }
    systemctl enable "$svc" >/dev/null 2>&1 || true
    systemctl restart "$svc" || { echo -e "$(localized_text "${RED}❌ ${svc} 重启失败。${PLAIN}" "${RED}❌ ${svc} Restart failed.${PLAIN}" "${RED}❌ ${svc} Не удалось перезапустить.${PLAIN}")"; return 1; }
}

stop_xray_entry_service_if_public_443() {
    local listener svc
    listener=$(detect_443_listener)
    listener_info_has_entry "$listener" "xray" || return 0
    svc=$(xray_entry_service_name) || return 0
    if ! systemctl stop "$svc"; then
        echo -e "$(localized_text "${RED}❌ 停止 ${svc} 失败，公网 443 仍可能被 Xray 占用。${PLAIN}" "${RED}❌ Stop ${svc} failed, public port 443 may still be occupied by Xray.${PLAIN}" "${RED}❌ Не удалось остановить ${svc}, публичный порт 443 всё ещё может быть занят Xray.${PLAIN}")"
        return 1
    fi
    sleep 1
    listener=$(detect_443_listener)
    if listener_info_has_entry "$listener" "xray"; then
        echo -e "$(localized_text "${RED}❌ ${svc} 已执行停止，但 Xray 仍在监听公网 443，拒绝继续切换入口。${PLAIN}" "${RED}❌ ${svc} has been executed and stopped, but Xray is still listening on the public port 443 and refuses to continue switching entries.${PLAIN}" "${RED}❌ ${svc} был выполнен и остановлен, но Xray все еще прослушивает публичный порт 443 и отказывается продолжать переключение входов.${PLAIN}")"
        return 1
    fi
}

stop_vpso_mux_service_if_public_443() {
    local listener
    local had_public_listener=false

    listener=$(detect_443_listener)
    if listener_info_has_entry "$listener" "tcppeek"; then
        had_public_listener=true
    fi

    if ! systemctl cat vpso-mux.service >/dev/null 2>&1 && [[ ! -f /etc/systemd/system/vpso-mux.service ]]; then
        $had_public_listener || return 0
        echo -e "$(localized_text "${RED}❌ 检测到 TCP Peek 占用公网 443，但未找到 vpso-mux.service。${PLAIN}" "${RED}❌ It was detected that TCP Peek occupied public port 443, but vpso-mux.service was not found.${PLAIN}" "${RED}❌ Было обнаружено, что TCP Peek занимает публичный порт 443, но vpso-mux.service не найден.${PLAIN}")"
        print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi

    systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
    write_vpso_mux_systemd_service || return 1
    systemctl disable --now vpso-mux >/dev/null 2>&1 || true
    if systemctl is-active --quiet vpso-mux; then
        echo -e "$(localized_text "${RED}❌ 停止 vpso-mux 失败，公网 443 仍可能被 TCP Peek 占用。${PLAIN}" "${RED}❌ Failed to stop vpso-mux, public port 443 may still be occupied by TCP Peek.${PLAIN}" "${RED}❌ Не удалось остановить vpso-mux, публичный порт 443 всё ещё может быть занят TCP Peek.${PLAIN}")"
        print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    if systemctl is-enabled --quiet vpso-mux; then
        echo -e "$(localized_text "${RED}❌ 禁用 vpso-mux 开机启动失败，重启后可能再次抢占公网 443。${PLAIN}" "${RED}❌ Disable vpso-mux Failed to start at boot, and may seize the public again after restarting 443.${PLAIN}" "${RED}❌ Отключить vpso-mux Не удалось запуститься при загрузке, и может снова захватить публичную сеть после перезапуска 443.${PLAIN}")"
        return 1
    fi
    systemctl reset-failed vpso-mux >/dev/null 2>&1 || true

    if $had_public_listener; then
        sleep 1
    fi
    listener=$(detect_443_listener)
    if listener_info_has_entry "$listener" "tcppeek"; then
        echo -e "$(localized_text "${RED}❌ vpso-mux 已执行停止并禁用，但 TCP Peek 仍在监听公网 443，拒绝继续切换入口。${PLAIN}" "${RED}❌ vpso-mux has been stopped and disabled, but TCP Peek is still listening on the public port 443 and refuses to continue switching entries.${PLAIN}" "${RED}❌ vpso-mux остановлен и отключен, но TCP Peek все еще прослушивает публичный порт 443 и отказывается продолжать переключение входов.${PLAIN}")"
        print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    echo -e "$(localized_text "${YELLOW}ℹ️ 已停止并禁用 vpso-mux 开机启动；非 TCP Peek 模式重启后不会抢占公网 443。${PLAIN}" "${YELLOW}ℹ️ Stopped and disabled vpso-mux startup; non-TCP Peek mode will not seize the public after restarting 443.${PLAIN}" "${YELLOW}ℹ️ Остановлен и отключен запуск vpso-mux; Режим, отличный от TCP Peek, не будет захватывать публичную сеть после перезапуска 443.${PLAIN}")"
}

stop_caddy_service_if_public_443() {
    local listener
    listener=$(detect_443_listener)
    listener_info_has_entry "$listener" "caddy" || return 0
    if ! systemctl stop caddy; then
        echo -e "$(localized_text "${RED}❌ 停止 caddy 失败，公网 443 仍可能被 Caddy 占用。${PLAIN}" "${RED}❌ Failed to stop caddy, public port 443 may still be occupied by Caddy.${PLAIN}" "${RED}❌ Не удалось остановить caddy, публичный порт 443 всё ещё может быть занят Caddy.${PLAIN}")"
        return 1
    fi
    sleep 1
    listener=$(detect_443_listener)
    if listener_info_has_entry "$listener" "caddy"; then
        echo -e "$(localized_text "${RED}❌ caddy 已执行停止，但仍在监听公网 443，拒绝继续切换入口。${PLAIN}" "${RED}❌ caddy has been stopped, but is still listening on the public port 443 and refuses to continue switching entries.${PLAIN}" "${RED}❌ caddy остановлен, но продолжает контролировать публичную сеть 443 и отказывается продолжать переключение входов.${PLAIN}")"
        return 1
    fi
}

disable_nginx_stream_public_443() {
    local nginx_conf="/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf"
    local listener
    [[ -e "$nginx_conf" ]] && quarantine_path "$nginx_conf" "/etc/vps-optimize/quarantine/nginx-sni" >/dev/null 2>&1 || true
    if command -v nginx >/dev/null 2>&1; then
        if ! nginx -t; then
            print_nginx_stream_failure_context "$NGINX_LISTEN_PORT"
            return 1
        fi
        if ! restart_service_if_available nginx; then
            print_nginx_stream_failure_context "$NGINX_LISTEN_PORT"
            return 1
        fi
        sleep 1
        listener=$(detect_443_listener)
        if listener_info_has_entry "$listener" "nginx"; then
            echo -e "$(localized_text "${RED}❌ Nginx Stream 443 配置已移除，但 nginx 仍在监听公网 443，拒绝继续切换入口。${PLAIN}" "${RED}❌ Nginx Stream 443 configuration has been removed, but nginx is still listening on the public port 443 and refuses to continue switching entries.${PLAIN}" "${RED}Конфигурация ❌ Nginx Stream 443 удалена, но nginx по-прежнему прослушивает публичный порт 443 и отказывается продолжать переключение входов.${PLAIN}")"
            print_nginx_stream_failure_context "$NGINX_LISTEN_PORT"
            return 1
        fi
        if systemctl is-active --quiet nginx; then
            echo -e "$(localized_text "${YELLOW}ℹ️ nginx 服务仍在运行，但已不监听公网 ${NGINX_LISTEN_PORT}；这是允许的，单入口只要求公网 443 由目标入口独占。${PLAIN}" "${YELLOW}ℹ️ nginx The service is still running, but it is no longer listening on the public ${NGINX_LISTEN_PORT}; this is allowed, and the shared entry only requires that public port 443 be exclusively occupied by the target entry.${PLAIN}" "${YELLOW}ℹ️ nginx Служба все еще работает, но больше не прослушивает публичную сеть ${NGINX_LISTEN_PORT}; это разрешено, и для общей точки входа требуется только, чтобы публичный порт 443 был занята исключительно целевым входом.${PLAIN}")"
        fi
    fi
}

stop_public_443_entry_services_for_target() {
    local target_mode="$1"
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1
    quarantine_legacy_nginx_https_proxy_configs
    stop_caddy_service_if_public_443 || return 1

    if [[ "$target_mode" != "nginx-stream" ]]; then
        disable_nginx_stream_public_443 || return 1
    fi
    if [[ "$target_mode" != "tcp-peek" ]]; then
        stop_vpso_mux_service_if_public_443 || return 1
    fi
    if [[ "$target_mode" != "xray-fallback" ]]; then
        stop_xray_entry_service_if_public_443 || return 1
    fi
}

guard_current_ssh_not_on_entry_port() {
    local action_name="$(localized_text "${1:-入口模式切换}" "${1:-入口模式切换}" "${1:-入口模式切换}")"
    local ssh_server_port
    if [[ -z "${SSH_CONNECTION:-}" ]]; then
        return 0
    fi
    ssh_server_port=$(printf '%s\n' "$SSH_CONNECTION" | awk '{print $4}')
    if [[ -n "$ssh_server_port" && "$ssh_server_port" == "${NGINX_LISTEN_PORT:-443}" ]]; then
        echo -e "$(localized_text "${RED}❌ 检测到当前 SSH 会话连接在入口端口 ${ssh_server_port}。${PLAIN}" "${RED}❌ Detected the current SSH session connected on ingress port ${ssh_server_port}.${PLAIN}" "${RED}❌ Обнаружен текущий сеанс SSH, подключенный к входному порту ${ssh_server_port}.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}${action_name} 会重启或替换该端口的入口服务，继续执行会直接断开当前 SSH。${PLAIN}" "${YELLOW}${action_name} will restart or replace the entry service of the port. Continued execution will directly disconnect the current SSH.${PLAIN}" "${YELLOW}${action_name} перезапустит или заменит службу входа в порт. Продолжение выполнения приведет к непосредственному отключению текущего SSH.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}请改用云厂商 VNC/Serial Console，或先用非 ${ssh_server_port} 的 SSH 端口登录后再执行。${PLAIN}" "${YELLOW}Please use the cloud vendor VNC/Serial Console instead, or log in using the SSH port other than ${ssh_server_port} before executing.${PLAIN}" "${YELLOW}Вместо этого используйте VNC/Serial Console поставщика облака или войдите в систему, используя порт SSH, отличный от ${ssh_server_port}, перед выполнением.${PLAIN}")"
        return 1
    fi
}

verify_public_443_listener_for_mode() {
    local mode="$1"
    local expected listener i
    local tries="${2:-10}"
    local delay="${3:-0.5}"
    mode=$(normalize_entry_mode_name "$mode") || return 1
    expected=$(entry_mode_expected_listener "$mode") || return 1

    for ((i = 1; i <= tries; i++)); do
        listener=$(detect_443_listener "$NGINX_LISTEN_PORT")
        if listener_info_has_entry "$listener" "$expected"; then
            return 0
        fi
        [[ "$i" -lt "$tries" ]] && sleep "$delay"
    done

    echo -e "$(localized_text "${RED}❌ 公网 443 监听不符合 ${mode}：期望 ${expected}，实际 ${listener#*|}${PLAIN}" "${RED}❌ public port 443 listening does not comply with ${mode}: expected ${expected}, actual ${listener#*|}${PLAIN}" "${RED}❌ прослушивание публичного порта 443 не соответствует ${mode}: ожидается ${expected}, факт ${listener#*|}${PLAIN}")"
    return 1
}

print_nginx_stream_failure_context() {
    local port="${1:-$NGINX_LISTEN_PORT}"
    local conf_file="/etc/nginx/stream.d/vps_sni_${port}.conf"
    echo -e "$(localized_text "${YELLOW}▶ Nginx Stream 未能稳定监听 ${port}，下面是最近状态和配置线索：${PLAIN}" "${YELLOW}▶ Nginx Stream failed to monitor ${port} stably. The following is the latest status and configuration clues:${PLAIN}" "${YELLOW}▶ Nginx Stream не удалось стабильно контролировать ${port}. Ниже приведены последние сведения о состоянии и конфигурации:.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}▶ 期望配置文件：${conf_file}${PLAIN}" "${YELLOW}▶ Expected profile: ${conf_file}${PLAIN}" "${YELLOW}▶ Ожидаемый профиль: ${conf_file}${PLAIN}")"
    if [[ -s "$conf_file" ]]; then
        sed -n '1,180p' "$conf_file" 2>/dev/null || true
    else
        echo -e "$(localized_text "${RED}❌ ${conf_file} 不存在或为空。${PLAIN}" "${RED}❌ ${conf_file} does not exist or is empty.${PLAIN}" "${RED}❌ ${conf_file} не существует или пуст.${PLAIN}")"
    fi
    echo -e "$(localized_text "${YELLOW}▶ nginx.conf 中的 stream/include 线索：${PLAIN}" "${YELLOW}▶ stream/include clue in nginx.conf:${PLAIN}" "${YELLOW}▶ трансляция/включение подсказки в nginx.conf:${PLAIN}")"
    grep -nE '^[[:space:]]*(stream[[:space:]]*\{|include[[:space:]]+/etc/nginx/stream\.d/\*\.conf;|include[[:space:]]+/etc/nginx/modules-enabled/\*\.conf;)' /etc/nginx/nginx.conf 2>/dev/null || true
    echo -e "$(localized_text "${YELLOW}▶ nginx -T 是否加载该 stream 文件：${PLAIN}" "${YELLOW}▶ nginx -T Whether to load the stream file:${PLAIN}" "${YELLOW}▶ nginx -T Загружать ли файл потока:${PLAIN}")"
    if nginx -T 2>&1 | grep -Fq "$conf_file"; then
        echo -e "$(localized_text "${GREEN}✅ nginx -T 已加载 ${conf_file}${PLAIN}" "${GREEN}✅ nginx -T Loaded ${conf_file}${PLAIN}" "${GREEN}✅ nginx -T Загружен ${conf_file}${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ nginx -T 未加载 ${conf_file}${PLAIN}" "${RED}❌ nginx -T not loaded ${conf_file}${PLAIN}" "${RED}❌ nginx -T не загружен ${conf_file}${PLAIN}")"
    fi
    echo -e "$(localized_text "${YELLOW}▶ nginx 服务状态：${PLAIN}" "${YELLOW}▶ nginx Service status:${PLAIN}" "${YELLOW}▶ nginx Статус сервиса:${PLAIN}")"
    systemctl status nginx --no-pager -l 2>/dev/null || true
    echo -e "$(localized_text "${YELLOW}▶ 最近 40 行 nginx 日志：${PLAIN}" "${YELLOW}▶ Last 40 lines nginx Log:${PLAIN}" "${YELLOW}▶ Последние 40 строк nginx Журнал:${PLAIN}")"
    journalctl -u nginx -n 40 --no-pager 2>/dev/null || true
    echo -e "$(localized_text "${YELLOW}▶ 当前 ${port} 监听情况：${PLAIN}" "${YELLOW}▶ Current listening status of ${port}:${PLAIN}" "${YELLOW}▶ Текущий статус прослушивания ${port}:${PLAIN}")"
    if command -v ss >/dev/null 2>&1; then
        ss -lntp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print}' || true
    else
        netstat -lntp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print}' || true
    fi
}

assert_nginx_stream_config_loaded() {
    local port="${1:-$NGINX_LISTEN_PORT}"
    local conf_file="/etc/nginx/stream.d/vps_sni_${port}.conf"

    if [[ ! -s "$conf_file" ]]; then
        echo -e "$(localized_text "${RED}❌ Nginx Stream 配置未生成或为空：${conf_file}${PLAIN}" "${RED}❌ Nginx Stream Configuration is not generated or empty: ${conf_file}${PLAIN}" "${RED}❌ Nginx Stream Конфигурация не создана или пуста: ${conf_file}${PLAIN}")"
        print_nginx_stream_failure_context "$port"
        return 1
    fi
    if ! nginx -T 2>&1 | grep -Fq "$conf_file"; then
        echo -e "$(localized_text "${RED}❌ Nginx 主配置没有实际加载 ${conf_file}，拒绝继续。${PLAIN}" "${RED}❌ Nginx The main configuration has not actually loaded ${conf_file}, refusing to continue.${PLAIN}" "${RED}❌ Nginx Основная конфигурация фактически не загрузила ${conf_file}, отказываясь продолжать работу.${PLAIN}")"
        print_nginx_stream_failure_context "$port"
        return 1
    fi
}

check_entry_mode_dependencies() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode") || { echo -e "$(localized_text "${RED}❌ 目标入口模式无效：${mode}${PLAIN}" "${RED}❌ Invalid target entry mode: ${mode}${PLAIN}" "${RED}❌ Неверный режим ввода цели: ${mode}${PLAIN}")"; return 1; }
    assert_web_proxy_whitelist_supported "$mode" "${WEB_PROXY_ENGINE:-caddy}" || return 1

    case "$mode" in
        "nginx-stream")
            command -v nginx >/dev/null 2>&1 || echo -e "$(localized_text "${YELLOW}未检测到 Nginx，切换时会沿用现有 Nginx stream 安装逻辑。${PLAIN}" "${YELLOW}Does not detect Nginx, and the existing Nginx stream installation logic will be used when switching.${PLAIN}" "${YELLOW}не обнаруживает Nginx, и при переключении будет использоваться существующая логика установки Nginx stream.${PLAIN}")"
            if [[ "$(current_web_proxy_engine)" == "caddy" ]]; then
                command -v caddy >/dev/null 2>&1 || echo -e "$(localized_text "${YELLOW}未检测到 Caddy，切换时会沿用现有 Caddy 安装逻辑。${PLAIN}" "${YELLOW}Does not detect Caddy, and the existing Caddy installation logic will be used when switching.${PLAIN}" "${YELLOW}не обнаруживает Caddy, и при переключении будет использоваться существующая логика установки Caddy.${PLAIN}")"
            fi
            ;;
        "tcp-peek")
            require_vpso_mux_binary_for_cutover || return 1
            if [[ "$(current_web_proxy_engine)" == "caddy" ]]; then
                command -v caddy >/dev/null 2>&1 || echo -e "$(localized_text "${YELLOW}未检测到 Caddy，切换时会沿用现有 Caddy 安装逻辑。${PLAIN}" "${YELLOW}Does not detect Caddy, and the existing Caddy installation logic will be used when switching.${PLAIN}" "${YELLOW}не обнаруживает Caddy, и при переключении будет использоваться существующая логика установки Caddy.${PLAIN}")"
            fi
            ;;
        "xray-fallback")
            xray_entry_service_name >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 未检测到 xray/x-ui/3x-ui systemd 服务，拒绝切换。${PLAIN}" "${RED}❌ xray/x-ui/3x-ui systemd service not detected, switching refused.${PLAIN}" "${RED}❌ xray/x-ui/3x-ui Служба systemd не обнаружена, в переключении отказано.${PLAIN}")"; return 1; }
            if [[ "$(current_web_proxy_engine)" == "caddy" ]]; then
                command -v caddy >/dev/null 2>&1 || echo -e "$(localized_text "${YELLOW}未检测到 Caddy，切换时会沿用现有 Caddy 安装逻辑。${PLAIN}" "${YELLOW}Does not detect Caddy, and the existing Caddy installation logic will be used when switching.${PLAIN}" "${YELLOW}не обнаруживает Caddy, и при переключении будет использоваться существующая логика установки Caddy.${PLAIN}")"
            fi
            ;;
    esac
}

backup_entry_mode_config() {
    local backup_dir="${1:-}" service_path svc listener_info
    create_sni_stack_backup "$backup_dir" >/dev/null
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    [[ -n "$backup_dir" && -d "$backup_dir" ]] || { echo -e "$(localized_text "${RED}❌ 入口模式切换备份失败。${PLAIN}" "${RED}❌ Entry mode switching backup failed.${PLAIN}" "${RED}❌ Не удалось переключить режим входа в резервную копию.${PLAIN}")"; return 1; }

    mkdir -p "$backup_dir/systemd" "$backup_dir/xray" "$backup_dir/vps-optimize"
    for svc in nginx.service caddy.service xray.service x-ui.service 3x-ui.service vpso-mux.service; do
        for service_path in "/etc/systemd/system/$svc" "/lib/systemd/system/$svc" "/usr/lib/systemd/system/$svc"; do
            [[ -f "$service_path" ]] && cp -a "$service_path" "$backup_dir/systemd/${service_path//\//_}" 2>/dev/null || true
        done
    done
    [[ -f /etc/xray/config.json ]] && cp -a /etc/xray/config.json "$backup_dir/xray/etc-xray-config.json" 2>/dev/null || true
    [[ -f /usr/local/etc/xray/config.json ]] && cp -a /usr/local/etc/xray/config.json "$backup_dir/xray/usr-local-etc-xray-config.json" 2>/dev/null || true
    [[ -f /etc/vps-optimize/xray-sni-routes.conf ]] && cp -a /etc/vps-optimize/xray-sni-routes.conf "$backup_dir/vps-optimize/xray-sni-routes.conf" 2>/dev/null || true
    listener_info=$(detect_443_listener)
    {
        echo "created_at=$(date -Is 2>/dev/null || date)"
        echo "entry_mode=$(get_entry_mode)"
        echo "listener=${listener_info}"
        echo "ss_443:"
        ss -lntp 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || echo "none"
    } > "$backup_dir/vps-optimize/443-listener-state.txt"
    echo "$backup_dir"
}

stop_vpso_mux_services_for_restore() {
    echo -e "$(localized_text "${YELLOW}▶ 正在停止 vpso-mux 相关服务，避免覆盖运行中的分流器二进制...${PLAIN}" "${YELLOW}▶ Stopping vpso-mux related services to avoid overwriting the running routing binary...${PLAIN}" "${YELLOW}▶ Остановка служб, связанных с vpso-mux, чтобы избежать перезаписи работающего двоичного файла маршрутизации...${PLAIN}")"
    systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
    systemctl stop vpso-mux >/dev/null 2>&1 || true
    sleep 1
}

rollback_last_entry_mode() {
    local backup_dir="${1:-}"
    local manual=0
    local old_mode=""
    if [[ -z "$backup_dir" ]]; then
        manual=1
        backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    fi
    if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
        echo -e "$(localized_text "${RED}❌ 未找到可回滚的入口模式备份。${PLAIN}" "${RED}❌ No rollbackable entry mode backup found.${PLAIN}" "${RED}❌ Не найдена резервная копия в режим входа с возможностью отката.${PLAIN}")"
        return 1
    fi
    if [[ -f "$backup_dir/vps-optimize/sni-stack.env" ]]; then
        old_mode=$(
            # shellcheck disable=SC1090
            unset ENTRY_MODE
            source "$backup_dir/vps-optimize/sni-stack.env" 2>/dev/null || true
            printf '%s' "${ENTRY_MODE:-nginx-stream}"
        )
        old_mode=$(normalize_entry_mode_name "$old_mode" 2>/dev/null || echo "nginx-stream")
    fi

    if [[ "$manual" -eq 1 ]]; then
        confirm_risk_action "$(localized_text "回滚上一次 443 入口模式切换" "Roll back the last 443 entry mode switch" "Откатить последний переключатель режима входа 443")" \
            "$(localized_text "Nginx/Caddy/Xray/vpso-mux 入口相关配置和服务状态" "Nginx/Caddy/Xray/vpso-mux entry-related configuration and service status" "Nginx/Caddy/Xray/vpso-mux конфигурация и состояние службы, связанные с точкой входа")" \
            "$(localized_text "再次切换入口模式，或用备份目录手动恢复" "Switch to entry mode again, or restore manually using the backup directory" "Снова переключитесь в режим входа или восстановите вручную, используя каталог резервной копии.")" \
            "$(localized_text "将使用备份目录 ${backup_dir} 覆盖当前入口配置。" "The current entry configuration will be overwritten with the backup directory ${backup_dir}." "Текущая конфигурация входа будет перезаписана резервным каталогом ${backup_dir}.")" || return 1
    fi

    echo -e "$(localized_text "${YELLOW}▶ 正在回滚上一次入口模式切换：${backup_dir}${PLAIN}" "${YELLOW}▶ Rolling back the last entry mode switch: ${backup_dir}${PLAIN}" "${YELLOW}▶ Откат последнего переключателя режима входа: ${backup_dir}${PLAIN}")"
    stop_vpso_mux_services_for_restore
    restore_sni_stack_backup_files "$backup_dir" || { echo -e "$(localized_text "${RED}❌ 回滚文件恢复失败。${PLAIN}" "${RED}❌ Rollback file recovery failed.${PLAIN}" "${RED}❌ Не удалось выполнить откат восстановления файла.${PLAIN}")"; return 1; }
    systemctl daemon-reload >/dev/null 2>&1 || true
    load_sni_stack_env >/dev/null 2>&1 || true
    old_mode=${old_mode:-$(get_entry_mode)}

    if ! stop_public_443_entry_services_for_target "$old_mode"; then
        echo -e "$(localized_text "${RED}❌ 回滚时未能停止冲突的公网 443 入口服务，请查看上面的诊断。${PLAIN}" "${RED}❌ The conflicting public port 443 entry service failed to stop during rollback, please check the diagnosis above.${PLAIN}" "${RED}❌ Не удалось остановить конфликтующую служба входа публичного порта 443 во время отката. Просмотрите диагностику выше.${PLAIN}")"
        return 1
    fi
    if ! apply_entry_mode_by_name "$old_mode" "$backup_dir"; then
        echo -e "$(localized_text "${RED}❌ 回滚到 ${old_mode} 时未能恢复公网 443 监听，请查看上面的诊断。${PLAIN}" "${RED}❌ Failed to restore public port 443 listening when rolling back to ${old_mode}, please check the diagnosis above.${PLAIN}" "${RED}❌ Не удалось восстановить прослушивание публичного порта 443 при откате к ${old_mode}, проверьте диагностику выше.${PLAIN}")"
        return 1
    fi
    set_entry_mode "$old_mode" >/dev/null 2>&1 || true
    write_single_443_engine_state "$(entry_mode_engine_name "$old_mode" 2>/dev/null || echo nginx-stream)" "$backup_dir"
    echo -e "$(localized_text "${GREEN}✅ 已回滚到上一次入口模式：${old_mode}${PLAIN}" "${GREEN}✅ Has rolled back to the last entry mode: ${old_mode}${PLAIN}" "${GREEN}✅ Откатился к последнему режиму входа: ${old_mode}${PLAIN}")"
}

apply_nginx_stream_mode() {
    local backup_dir="${1:-}"
    install_nginx_stream_stack || return 1
    harden_nginx_public_errors
    apply_web_proxy_configs_for_single_443 || return 1
    cleanup_old_nginx_sni_stream_configs
    write_nginx_sni_stream_config || return 1
    assert_nginx_stream_config_loaded "$NGINX_LISTEN_PORT" || return 1
    if [[ "$(current_web_proxy_engine)" == "caddy" ]]; then
        restart_web_proxy_for_single_443 || return 1
    fi
    if ! systemctl enable nginx >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}❌ nginx 开机启动设置失败，拒绝将本次启动误报为可持久入口。${PLAIN}" "${RED}❌ nginx The startup setting failed and the startup was rejected as a persistent entry.${PLAIN}" "${RED}❌ nginx Не удалось настроить запуск, и запуск был отклонен как постоянная запись.${PLAIN}")"
        return 1
    fi
    if ! systemctl restart nginx; then
        print_nginx_stream_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    if ! verify_public_443_listener_for_mode "nginx-stream"; then
        print_nginx_stream_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    probe_tls_sni_certificate "$(localized_text "Nginx Stream 面板 SNI" "Nginx Stream panel SNI" "Панель Nginx Stream SNI")" "$(probe_host_for_listen_addr "$NGINX_LISTEN_ADDR")" "$NGINX_LISTEN_PORT" "$PANEL_DOMAIN" || return 1
    tcp_probe_host "$(localized_text "$(web_proxy_engine_label) 本地 TLS" "$(web_proxy_engine_label) local TLS" "$(web_proxy_engine_label) локальный TLS")" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    if xray_entry_service_name >/dev/null 2>&1; then
        restart_xray_entry_service || echo -e "$(localized_text "${YELLOW}⚠️ Xray/3x-ui 服务重启失败；Nginx Stream/Web 入口已恢复，请单独检查 Xray 入站。${PLAIN}" "${YELLOW}⚠️ Xray/3x-ui service failed to restart; Nginx Stream/Web entry has been restored, please check Xray inbound separately.${PLAIN}" "${YELLOW}⚠️ Службу Xray/3x-ui не удалось перезапустить; Вход Nginx Stream/Web восстановлен, проверьте входящий Xray отдельно.${PLAIN}")"
    fi
    if ! tcp_probe_host "$(localized_text "Xray/REALITY 本地入站" "Xray/REALITY local inbound" "Xray/REALITY локальное входящее подключение")" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1; then
        echo -e "$(localized_text "${YELLOW}⚠️ Nginx Stream/Web 入口已恢复，但 Xray/REALITY 本地入站未连通。${PLAIN}" "${YELLOW}⚠️ Nginx Stream/Web ingress has been restored, but Xray/REALITY local inbound is not connected.${PLAIN}" "${YELLOW}⚠️ Вход Nginx Stream/Web восстановлен, но локальное входящее подключение Xray/REALITY не подключен.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}请在 3x-ui/Xray 确认本地入站正在监听 ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}，或把脚本里的 Xray 本地端口改成实际值。${PLAIN}" "${YELLOW}Please confirm that the local inbound port is listening ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT} at 3x-ui/Xray, or change the Xray local port in the script to the actual value.${PLAIN}" "${YELLOW}Подтвердите, что локальный входящий порт прослушивает ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT} по адресу 3x-ui/Xray, или измените локальный порт Xray в сценарии на фактическое значение.${PLAIN}")"
    fi
    write_single_443_engine_state "nginx-stream" "$backup_dir"
}

apply_tcppeek_mode() {
    local backup_dir="${1:-}"
    local tmp_config
    require_vpso_mux_binary_for_cutover || return 1
    warn_if_public_bind "$(web_proxy_engine_label)" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    apply_web_proxy_configs_for_single_443 || return 1
    restart_web_proxy_for_single_443 || return 1
    tmp_config="/etc/vps-optimize/vpso-mux.yaml.tmp.$$"
    write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$tmp_config" || return 1
    run_vpso_mux_config_check "$tmp_config" || { quarantine_path "$tmp_config" "/etc/vps-optimize/quarantine/vpso-mux" >/dev/null 2>&1 || true; return 1; }
    set_entry_mode "tcp-peek" || return 1
    write_vpso_mux_systemd_service
    mv "$tmp_config" "$(vpso_mux_config_path)" || return 1
    if ! systemctl enable vpso-mux >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}❌ vpso-mux 开机启动设置失败，拒绝将本次启动误报为可持久入口。${PLAIN}" "${RED}❌ vpso-mux The startup setting failed and the startup was rejected as a persistent entry.${PLAIN}" "${RED}❌ vpso-mux Не удалось настроить запуск, и запуск был отклонен как постоянная запись.${PLAIN}")"
        return 1
    fi
    if ! systemctl restart vpso-mux; then
        print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    if ! verify_public_443_listener_for_mode "tcp-peek"; then
        print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    probe_tls_sni_certificate "$(localized_text "TCP Peek 面板 SNI" "TCP Peek panel SNI" "Панель TCP Peek SNI")" "$(probe_host_for_listen_addr "$NGINX_LISTEN_ADDR")" "$NGINX_LISTEN_PORT" "$PANEL_DOMAIN" || return 1
    tcp_probe_host "$(localized_text "$(web_proxy_engine_label) 本地 TLS" "$(web_proxy_engine_label) local TLS" "$(web_proxy_engine_label) локальный TLS")" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    if xray_entry_service_name >/dev/null 2>&1; then
        restart_xray_entry_service || return 1
    fi
    tcp_probe_host "$(localized_text "Xray/REALITY 本地入站" "Xray/REALITY local inbound" "Xray/REALITY локальное входящее подключение")" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1 || return 1
    write_single_443_engine_state "tcp-peek" "$backup_dir"
}

apply_xray_fallback_mode() {
    local backup_dir="${1:-}"
    apply_web_proxy_configs_for_single_443 || return 1
    restart_web_proxy_for_single_443 || return 1
    restart_xray_entry_service || return 1
    verify_public_443_listener_for_mode "xray-fallback" || return 1
    tcp_probe_host "$(localized_text "$(web_proxy_engine_label) fallback 后端" "$(web_proxy_engine_label) fallback backend" "Резервный сервер $(web_proxy_engine_label)")" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    probe_tls_sni_certificate "$(localized_text "Xray Fallback 面板 SNI" "Xray Fallback panel SNI" "Xray Резервная панель SNI")" "$(probe_host_for_listen_addr "$NGINX_LISTEN_ADDR")" "$NGINX_LISTEN_PORT" "$PANEL_DOMAIN" || return 1
    write_single_443_engine_state "xray-fallback" "$backup_dir"
}

apply_entry_mode_by_name() {
    local target_mode="$1"
    local backup_dir="${2:-}"
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1
    case "$target_mode" in
        "nginx-stream") apply_nginx_stream_mode "$backup_dir" ;;
        "xray-fallback") apply_xray_fallback_mode "$backup_dir" ;;
        "tcp-peek") apply_tcppeek_mode "$backup_dir" ;;
    esac
}

select_initial_entry_mode() {
    local choice tcppeek_bootstrap
    ENTRY_MODE="nginx-stream"

    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}选择本次首次配置使用的 443 入口模式${PLAIN}" "${BOLD}Select the 443 entry mode used for this first configuration${PLAIN}" "${BOLD}Выберите режим входа 443, используемый для этой первой конфигурации.${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${GREEN}  1. Nginx Stream 模式${PLAIN}       ${YELLOW}(默认稳定模式，适合大多数用户)${PLAIN}" "${GREEN}1. Nginx Stream mode (default stable mode, suitable for most users)${PLAIN}" "${GREEN}1. Режим Nginx Stream (стабильный режим по умолчанию, подходит для большинства пользователей)${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  2. Xray Fallback 模式${PLAIN}      ${YELLOW}(需你已在 Xray/3x-ui 准备好公网 443 主入站)${PLAIN}" "${GREEN}2. Xray Fallback mode (you need to prepare the public port 443 main inbound in Xray/3x-ui)${PLAIN}" "${GREEN}2. Xray Резервный режим (необходимо подготовить основное входящее подключение публичного порта 443 в Xray/3x-ui)${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  3. TCP Peek + Splice 模式${PLAIN}  ${YELLOW}(首次安装会先提示安装/使用 Nginx Stream，再跑 8444 预检后切换)${PLAIN}" "${GREEN}3. TCP Peek + Splice mode (the first installation will prompt you to install/use Nginx Stream, and then run 8444 to preflight check and switch)${PLAIN}" "${GREEN}3. Режим TCP Peek + Splice (при первой установке вам будет предложено установить/использовать Nginx Stream, а затем запустить 8444 для предварительной проверки и переключения)${PLAIN}")"
    echo -e "$(localized_text "${RED}  0. 取消${PLAIN}" "${RED}0. Cancel${PLAIN}" "${RED}0. Отмена${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    read_trimmed choice "$(localized_text "请选择入口模式（默认 1）: " "Please select entry mode (default 1):" "Пожалуйста, выберите режим входа (по умолчанию 1):")"
    case "${choice:-1}" in
        1) ENTRY_MODE="nginx-stream" ;;
        2) ENTRY_MODE="xray-fallback" ;;
        3)
            echo -e "$(localized_text "${YELLOW}TCP Peek 首次接管 443 前必须先安装/使用 Nginx Stream，建立可用的共享配置和 Nginx/Caddy 基线。${PLAIN}" "${YELLOW}TCP Peek Before taking over 443 for the first time, Nginx Stream must be installed/used to establish the available shared configuration and Nginx/Caddy baseline.${PLAIN}" "${YELLOW}TCP Peek Прежде чем впервые взять под контроль 443, необходимо установить/использовать Nginx Stream для установки доступной общей конфигурации и базовой линии Nginx/Caddy.${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}推荐流程：先安装/使用 Nginx Stream 完成首次安装，再进入 [19] -> [16] 做 8444 预检，最后用 [5] 切换到 TCP Peek。${PLAIN}" "${YELLOW}Recommended process for : First install/use Nginx Stream to complete the first installation, then enter [19] -> [16] to do 8444 preflight check, and finally use [5] to switch to TCP Peek.${PLAIN}" "${YELLOW}Рекомендуемый процесс для : сначала установите/используйте Nginx Stream для завершения первой установки, затем введите [19] -> [16] для выполнения предварительной проверки 8444 и, наконец, используйте [5] для переключения на TCP Peek.${PLAIN}")"
            read_trimmed tcppeek_bootstrap "$(localized_text "是否先安装/使用 Nginx Stream 完成本次首次安装？(Y/n，默认 yes): " "Do you want to install/use Nginx Stream first to complete this first installation? (Y/n, default yes):" "Хотите ли вы сначала установить/использовать Nginx Stream, чтобы завершить первую установку? (Да/нет, по умолчанию да):")"
            tcppeek_bootstrap="${tcppeek_bootstrap:-yes}"
            if is_yes "$tcppeek_bootstrap"; then
                ENTRY_MODE="nginx-stream"
            else
                echo -e "$(localized_text "${BLUE}已取消首次配置。${PLAIN}" "${BLUE}Has been canceled for the first time.${PLAIN}" "${BLUE}отменен впервые.${PLAIN}")"
                return 1
            fi
            ;;
        0|q|Q) echo -e "$(localized_text "${BLUE}已取消首次配置。${PLAIN}" "${BLUE}Has been canceled for the first time.${PLAIN}" "${BLUE}отменен впервые.${PLAIN}")"; return 1 ;;
        *) echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"; return 1 ;;
    esac
    echo -e "$(localized_text "${GREEN}✅ 已选择 443 入口模式：${ENTRY_MODE}${PLAIN}" "${GREEN}✅ 443 entry mode selected: ${ENTRY_MODE}${PLAIN}" "${GREEN}Выбран 443 режима входа: ${ENTRY_MODE}${PLAIN}")"
}

prepare_initial_entry_mode_dependencies() {
    local target_mode="$1"
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1
    case "$target_mode" in
        "tcp-peek")
            require_vpso_mux_binary_for_cutover || {
                echo -e "$(localized_text "${YELLOW}首次配置阶段尚未有共享配置可用于 8444 预检；请先选择 Nginx Stream 完成首次配置，再运行 [19] -> [16] 预检，最后用 [5] 切换到 TCP Peek。${PLAIN}" "${YELLOW}During the first configuration phase of , there is no shared configuration available for 8444 preflight; please select Nginx Stream to complete the first configuration, then run [19] -> [16] preflight, and finally use [5] to switch to TCP Peek.${PLAIN}" "${YELLOW}На первом этапе настройки общая конфигурация для предполетной подготовки 8444 недоступна; пожалуйста, выберите Nginx Stream, чтобы завершить первую настройку, затем запустите [19] -> [16] предварительная проверка и, наконец, используйте [5] для переключения на TCP Peek.${PLAIN}")"
                return 1
            }
            ;;
        "xray-fallback")
            xray_entry_service_name >/dev/null 2>&1 || {
                echo -e "$(localized_text "${RED}❌ 未检测到 xray/x-ui/3x-ui systemd 服务，无法首次配置为 xray-fallback。${PLAIN}" "${RED}❌ The xray/x-ui/3x-ui systemd service is not detected and cannot be configured as xray-fallback for the first time.${PLAIN}" "${RED}❌ Служба xray/x-ui/3x-ui systemd не обнаружена и не может быть настроена как резервная служба xray в первый раз.${PLAIN}")"
                echo -e "$(localized_text "${YELLOW}请先在 [5 面板、节点与订阅工具] 中安装并配置 Xray/3x-ui 主入站，或改选 Nginx Stream 模式 / TCP Peek + Splice 模式。${PLAIN}" "${YELLOW}Please first install and configure Xray/3x-ui main inbound in [5 Panels, Nodes and Subscription Tools], or change to Nginx Stream mode / TCP Peek + Splice mode.${PLAIN}" "${YELLOW}Сначала установите и настройте основное входящее подключение Xray/3x-ui в [5 панелей, узлов и инструментов подписки] или переключитесь в режим Nginx Stream/TCP Peek + Splice.${PLAIN}")"
                return 1
            }
            print_xray_fallback_mode_explanation
            confirm_risk_action "$(localized_text "首次配置使用 Xray Fallback 模式" "initial setup using Xray Fallback mode" "Первая настройка с использованием резервного режима Xray.")" \
                "$(localized_text "公网 443 将由已有 Xray 主入站接管，普通 HTTPS fallback 到所选 Web 反代引擎" "public port 443 will be taken over by the existing Xray main inbound, and ordinary HTTPS fallback to the selected Web reverse proxy engine" "публичный порт 443 будет занят существующей основным входящим подключением Xray и обычным резервным HTTPS для выбранного механизма обратный прокси веб-сети.")" \
                "$(localized_text "返回首次配置并选择 Nginx Stream 模式或 TCP Peek + Splice 模式" "Return to the first configuration and select Nginx Stream mode or TCP Peek + Splice mode" "Вернитесь к первой конфигурации и выберите режим Nginx Stream или режим TCP Peek + Splice.")" \
                "$(localized_text "确认你已经在 Xray/3x-ui 中准备好公网 443 主入站；脚本不会创建或修改 3x-ui/Xray 入站内部配置。" "Confirm that you have prepared the public port 443 main inbound in Xray/3x-ui; the script will not create or modify the 3x-ui/Xray inbound internal configuration." "Подтвердите, что вы подготовили главный вход 443 публичной сети в Xray/3x-ui; сценарий не будет создавать или изменять входящую внутреннюю конфигурацию 3x-ui/Xray.")" || return 1
            ;;
    esac
}

switch_entry_mode() {
    local target_mode="$1"
    local current_mode backup_dir planned_backup_dir yn
    load_sni_stack_env || return 1
    target_mode=$(normalize_entry_mode_name "$target_mode") || { echo -e "$(localized_text "${RED}❌ 目标入口模式无效：${target_mode}${PLAIN}" "${RED}❌ Invalid target entry mode: ${target_mode}${PLAIN}" "${RED}❌ Неверный режим ввода цели: ${target_mode}${PLAIN}")"; return 1; }
    current_mode=$(get_entry_mode)

    if [[ "$target_mode" == "$current_mode" ]]; then
        read_trimmed yn "$(localized_text "当前已经是 ${target_mode}，是否重新应用当前模式？(Y/n，默认 y): " "The current value is ${target_mode}. Do you want to reapply the current mode? (Y/n, default y):" "Текущее значение — ${target_mode}. Вы хотите повторно применить текущий режим? (Да/нет, по умолчанию y):")"
        is_yes "$yn" && reapply_current_entry_mode
        return $?
    fi

    echo -e "$(localized_text "${CYAN}准备切换 443 入口模式：${current_mode} -> ${target_mode}${PLAIN}" "${CYAN}Is ready to switch 443 Entry mode: ${current_mode} -> ${target_mode}${PLAIN}" "${CYAN}готов переключить режим ввода 443: ${current_mode} -> ${target_mode}${PLAIN}")"
    check_entry_mode_dependencies "$target_mode" || return 1
    if [[ "$target_mode" == "xray-fallback" ]]; then
        select_xray_fallback_main_route_for_switch || return 1
    fi
    planned_backup_dir=$(sni_stack_backup_dir)
    preview_entry_mode_cutover "$current_mode" "$target_mode" "$planned_backup_dir" || return 1
    guard_current_ssh_not_on_entry_port "$(localized_text "切换 443 入口模式" "Switch 443 entry mode" "Переключить 443 режим входа")" || return 1
    backup_dir=$(backup_entry_mode_config "$planned_backup_dir") || return 1
    if ! preflight_entry_mode_before_cutover "$target_mode"; then
        echo -e "$(localized_text "${RED}❌ 入口模式 ${target_mode} 预检失败，公网 443 未切换。${PLAIN}" "${RED}❌ entry mode ${target_mode} preflight check failed, public port 443 was not switched.${PLAIN}" "${RED}❌ Режим входа ${target_mode} Предварительная проверка не удалась, публичный порт 443 не был переключён.${PLAIN}")"
        return 1
    fi

    if ! stop_public_443_entry_services_for_target "$target_mode"; then
        echo -e "$(localized_text "${RED}❌ 停止当前公网 443 入口服务失败，正在回滚。${PLAIN}" "${RED}❌ Stop the current public port 443. The entry service failed and is being rolled back.${PLAIN}" "${RED}❌ Не удалось остановить текущую службу входа в публичный порт 443, и выполняется откат.${PLAIN}")"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi

    if ! apply_entry_mode_by_name "$target_mode" "$backup_dir"; then
        echo -e "$(localized_text "${RED}❌ 入口模式 ${target_mode} 应用失败，正在自动回滚。${PLAIN}" "${RED}❌ Entry mode ${target_mode} The application failed and is being rolled back automatically.${PLAIN}" "${RED}❌ Режим входа ${target_mode} Ошибка приложения, и выполняется автоматический откат.${PLAIN}")"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi

    ENTRY_MODE="$target_mode"
    save_sni_stack_env
    write_single_443_engine_state "$(entry_mode_engine_name "$target_mode")" "$backup_dir"
    echo -e "$(localized_text "${GREEN}✅ 443 入口模式已切换为：${target_mode}${PLAIN}" "${GREEN}✅ 443 The entry mode has been switched to: ${target_mode}${PLAIN}" "${GREEN}✅ 443 Режим входа переключен на: ${target_mode}${PLAIN}")"
    show_current_entry_status
}

reapply_current_entry_mode() {
    local current_mode backup_dir planned_backup_dir assume_yes
    assume_yes="${1:-}"
    load_sni_stack_env || return 1
    current_mode=$(get_entry_mode)
    current_mode=$(normalize_entry_mode_name "$current_mode") || { echo -e "$(localized_text "${RED}❌ 当前 ENTRY_MODE 无效：${current_mode}${PLAIN}" "${RED}❌ Current ENTRY_MODE is invalid: ${current_mode}${PLAIN}" "${RED}❌ Текущий ENTRY_MODE недействителен: ${current_mode}${PLAIN}")"; return 1; }
    echo -e "$(localized_text "${CYAN}正在重新应用当前 443 入口模式：${current_mode}${PLAIN}" "${CYAN}Is reapplying the current 443 entry mode: ${current_mode}${PLAIN}" "${CYAN}повторно применяет текущий режим ввода 443: ${current_mode}.${PLAIN}")"
    guard_current_ssh_not_on_entry_port "$(localized_text "重新应用 443 入口模式" "Reapply 443 entry mode" "Повторно применить режим входа 443")" || return 1
    if [[ "$assume_yes" != "--yes" ]]; then
        planned_backup_dir=$(sni_stack_backup_dir)
        preview_entry_mode_cutover "$current_mode" "$current_mode" "$planned_backup_dir" || return 1
    fi
    check_entry_mode_dependencies "$current_mode" || return 1
    planned_backup_dir="${planned_backup_dir:-$(sni_stack_backup_dir)}"
    backup_dir=$(backup_entry_mode_config "$planned_backup_dir") || return 1
    if [[ "$current_mode" == "xray-fallback" ]]; then
        select_xray_fallback_main_route_for_switch || return 1
    fi
    if ! preflight_entry_mode_before_cutover "$current_mode"; then
        echo -e "$(localized_text "${RED}❌ 当前入口模式 ${current_mode} 预检失败，公网 443 未重新应用。${PLAIN}" "${RED}❌ Current entry mode ${current_mode} preflight failed, public port 443 has not been reapplied.${PLAIN}" "${RED}❌ Текущий режим входа. Не удалось выполнить предварительную проверку ${current_mode}, конфигурация публичного порта 443 не была применена повторно.${PLAIN}")"
        return 1
    fi
    if ! stop_public_443_entry_services_for_target "$current_mode"; then
        echo -e "$(localized_text "${RED}❌ 停止当前公网 443 入口服务失败，正在回滚。${PLAIN}" "${RED}❌ Stop the current public port 443. The entry service failed and is being rolled back.${PLAIN}" "${RED}❌ Не удалось остановить текущую службу входа в публичный порт 443, и выполняется откат.${PLAIN}")"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi
    if ! apply_entry_mode_by_name "$current_mode" "$backup_dir"; then
        echo -e "$(localized_text "${RED}❌ 当前入口模式重新应用失败，正在自动回滚。${PLAIN}" "${RED}❌ The current entry mode failed to be reapplied and is being automatically rolled back.${PLAIN}" "${RED}❌ Не удалось повторно применить текущий режим входа, и выполняется автоматический откат.${PLAIN}")"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi
    ENTRY_MODE="$current_mode"
    save_sni_stack_env
    write_single_443_engine_state "$(entry_mode_engine_name "$current_mode")" "$backup_dir"
    echo -e "$(localized_text "${GREEN}✅ 当前入口模式已重新应用：${current_mode}${PLAIN}" "${GREEN}✅ The current entry mode has been reapplied: ${current_mode}${PLAIN}" "${GREEN}. Текущий режим входа был применен повторно: ${current_mode}.${PLAIN}")"
    show_current_entry_status
}

view_vpso_mux_logs() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}📜 vpso-mux 日志${PLAIN}" "${BOLD}📜 vpso-mux Log${PLAIN}" "${BOLD}📜 vpso-mux Журнал${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    journalctl -u vpso-mux -n 120 --no-pager 2>/dev/null || echo "$(localized_text "未读取到 vpso-mux 日志。" "The vpso-mux log was not read." "Журнал vpso-mux не был прочитан.")"
}

entry_mode_supports_xray_sni_routes() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode" 2>/dev/null) || return 1
    [[ "$mode" == "nginx-stream" || "$mode" == "tcp-peek" ]]
}
