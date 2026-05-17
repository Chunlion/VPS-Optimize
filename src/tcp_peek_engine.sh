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

    echo -e "${CYAN}▶ 检查 TCP Peek 8444 路由矩阵...${PLAIN}"
    probe_tls_sni_certificate "TCP Peek 8444 面板 SNI 预检" "$connect_host" "$test_port" "$PANEL_DOMAIN" || failures=1

    for domain in "${SITE_DOMAINS[@]}"; do
        [[ -n "$domain" ]] || continue
        probe_tls_sni_certificate "TCP Peek 8444 Web SNI 预检 ${domain}" "$connect_host" "$test_port" "$domain" || failures=1
    done

    tcp_probe_host "TCP Peek 默认 Xray/REALITY 后端" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 3 1 || failures=1

    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        route_addr="${TCP_ROUTE_ADDRS[$i]}"
        route_port="${TCP_ROUTE_PORTS[$i]}"
        [[ -n "$domain" && -n "$route_addr" && -n "$route_port" ]] || continue
        tcp_probe_host "TCP Peek 本地 TCP/SNI 后端 ${domain}" "$(probe_host_for_listen_addr "$route_addr")" "$route_port" 3 1 || failures=1
    done

    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        route_addr="${XRAY_SNI_ROUTE_ADDRS[$i]}"
        route_port="${XRAY_SNI_ROUTE_PORTS[$i]}"
        [[ -n "$domain" && -n "$route_addr" && -n "$route_port" ]] || continue
        tcp_probe_host "TCP Peek Xray SNI 后端 ${domain}" "$(probe_host_for_listen_addr "$route_addr")" "$route_port" 3 1 || failures=1
    done

    if [[ "$failures" -ne 0 ]]; then
        echo -e "${RED}❌ TCP Peek 8444 路由矩阵预检失败，公网 443 未改动。${PLAIN}"
        return 1
    fi
    echo -e "${GREEN}✅ TCP Peek 8444 路由矩阵预检通过。${PLAIN}"
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
        echo -e "${RED}❌ TCP Peek 8444 预检服务启动失败，公网 443 未改动。${PLAIN}"
        return 1
    fi
    sleep 1
    if ! port_listener_has_process "$test_port" 'vpso-mux'; then
        systemctl stop vpso-mux-preflight >/dev/null 2>&1 || true
        echo -e "${RED}❌ TCP Peek 8444 预检未监听到 vpso-mux，拒绝切换公网 443。${PLAIN}"
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
    echo -e "${BOLD}TCP Peek + Splice 分流规则校验${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    local config_file
    config_file=$(vpso_mux_config_path)
    [[ -f "$config_file" ]] || { echo -e "${YELLOW}未找到 ${config_file}，正在先生成配置。${PLAIN}"; write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$config_file" || return 1; }
    echo -e "${CYAN}▶ 校验 YAML、SNI、backend、whitelist 和重复 SNI...${PLAIN}"
    run_vpso_mux_config_check "$config_file" || return 1
    echo -e "${CYAN}▶ 检查本地后端端口...${PLAIN}"
    tcp_probe_host "Caddy 127.0.0.1:${CADDY_LISTEN_PORT}" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || true
    tcp_probe_host "Xray/REALITY 127.0.0.1:${XRAY_LISTEN_PORT}" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" || true
    print_sni_ip_whitelist_summary
    echo -e "${GREEN}✅ 配置校验完成。请先使用 TCP Peek + Splice 测试入口验证，不要直接接管 443。${PLAIN}"
}

start_tcp_peek_test_port() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}TCP Peek + Splice 状态 / 测试入口${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    if ! load_sni_stack_env; then
        NGINX_LISTEN_PORT="${NGINX_LISTEN_PORT:-443}"
        show_vpso_mux_runtime_status
        return 1
    fi
    show_vpso_mux_runtime_status
    echo -e "------------------------------------------------"
    if [[ "$(single_443_current_engine)" == "tcp-peek" ]]; then
        echo -e "${YELLOW}当前入口已经是 TCP Peek + Splice 模式。为避免误停公网 443，本入口不覆盖运行中的 443 配置。${PLAIN}"
        return 0
    fi
    echo -e "${YELLOW}vpso-mux 预检服务只监听 8444，当前公网 443 入口不会被停止或替换。${PLAIN}"
    confirm_risk_action "安装/构建 vpso-mux 并启动 8444 预检" \
        "可能安装 Go 工具链、构建 /usr/local/bin/vpso-mux，并启动独立 vpso-mux-preflight.service 监听 8444" \
        "停止 vpso-mux-preflight.service，或继续使用 Nginx Stream / Xray Fallback，不会改动公网 443" \
        "低内存或低磁盘机器会被资源预检查拦截；公网 443 在本步骤不会被替换。" || return 1
    install_vpso_mux_binary || return 1
    apply_caddy_configs_for_single_443 || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    tcp_probe_host "Xray/REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1 || return 1
    run_tcppeek_preflight_service 1 "8444" || return 1
    echo -e "${GREEN}✅ vpso-mux 预检服务已启动在测试端口 8444，公网 443 未改动。${PLAIN}"
    echo -e "测试命令："
    echo -e "  openssl s_client -connect SERVER_IP:8444 -servername ${PANEL_DOMAIN}"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  openssl s_client -connect SERVER_IP:8444 -servername ${SITE_DOMAINS[0]}"
    echo -e "  openssl s_client -connect SERVER_IP:8444 -servername random.example.com"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  curl -vk --resolve ${SITE_DOMAINS[0]}:8444:SERVER_IP https://${SITE_DOMAINS[0]}:8444/"
}

preflight_tcppeek_before_cutover() {
    echo -e "${CYAN}▶ 正在执行 TCP Peek 8444 安全预检，公网 443 暂不改动...${PLAIN}"
    require_vpso_mux_binary_for_cutover || return 1
    warn_if_public_bind "Caddy" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    apply_caddy_configs_for_single_443 || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    tcp_probe_host "Xray/REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1 || {
        echo -e "${RED}❌ Xray 本地入站不可达，拒绝切换 TCP Peek。请先在 3x-ui/Xray 中准备本地监听入站。${PLAIN}"
        return 1
    }
    run_tcppeek_preflight_service 0 "8444" || return 1
    echo -e "${GREEN}✅ TCP Peek 8444 预检通过，才会进入公网 443 切换。${PLAIN}"
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
    echo -e "${BOLD}将涉及的配置路径${PLAIN}"
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
    echo -e "状态：$(single_443_engine_state_path)"
    echo -e "共享参数：/etc/vps-optimize/sni-stack.env"
    if [[ "$target_mode" == "tcp-peek" ]]; then
        echo -e "vpso-mux 状态：$(vpso_mux_status_json_path)"
    fi
}

print_preview_file_diff() {
    local actual_path="$1"
    local planned_path="$2"
    local title="$3"

    echo -e "${CYAN}--- ${title}${PLAIN}"
    if ! command -v diff >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 diff 命令，无法显示文本差异。${PLAIN}"
        return 0
    fi

    if [[ -f "$actual_path" && -f "$planned_path" ]]; then
        diff -u --label "${actual_path} (当前)" --label "${actual_path} (预计)" "$actual_path" "$planned_path" || true
    elif [[ -f "$actual_path" && ! -f "$planned_path" ]]; then
        diff -u --label "${actual_path} (当前)" --label "${actual_path} (预计停用)" "$actual_path" /dev/null || true
    elif [[ ! -f "$actual_path" && -f "$planned_path" ]]; then
        diff -u --label "${actual_path} (当前不存在)" --label "${actual_path} (预计新增)" /dev/null "$planned_path" || true
    else
        echo "当前和预计都没有该文件。"
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
    echo -e "${BOLD}443 单入口切换 diff 预览${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    print_preview_file_diff "/etc/caddy/Caddyfile" "$target_caddyfile" "Caddyfile"
    print_preview_file_diff "/etc/caddy/conf.d/${PANEL_DOMAIN}.caddy" "${target_caddy_dir}/${PANEL_DOMAIN}.caddy" "Caddy 面板域名"
    local site_domain
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ -n "$site_domain" ]] || continue
        print_preview_file_diff "/etc/caddy/conf.d/${site_domain}.caddy" "${target_caddy_dir}/${site_domain}.caddy" "Caddy 网站/反代 ${site_domain}"
    done
    print_preview_file_diff "/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf" "$target_nginx" "Nginx Stream 入口"
    print_preview_file_diff "$(vpso_mux_config_path)" "$target_mux" "vpso-mux 分流配置"
    print_preview_file_diff "/etc/systemd/system/vpso-mux.service" "$target_service" "vpso-mux systemd"
    echo -e "${YELLOW}diff 预览只在临时目录生成目标文件，不会写入 /etc。临时目录：${tmp_dir}${PLAIN}"
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
        echo -e "${BOLD}443 单入口切换变更预览${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "当前 ENTRY_MODE：${current_mode}"
        echo -e "目标 ENTRY_MODE：${target_mode}"
        echo -e "当前 443 监听者：${current_display} (${listener_info#*|})"
        echo -e "切换后预计监听者：${expected_display}"
        echo -e "回滚点位置：${backup_dir}"
        echo -e "------------------------------------------------"
        print_entry_mode_cutover_paths "$target_mode"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看 diff${PLAIN}"
        echo -e "${GREEN}  2. 继续切换${PLAIN}"
        echo -e "${RED}  0. 取消，不修改任何配置${PLAIN}"
        read_trimmed choice "请选择操作（默认 0 取消）: "
        case "$(echo "${choice:-0}" | tr '[:upper:]' '[:lower:]')" in
            1|d|D|diff)
                show_entry_mode_cutover_diff "$target_mode"
                ;;
            2|y|yes)
                return 0
                ;;
            0|n|no|q)
                echo -e "${BLUE}已取消 443 入口切换，未修改任何配置。${PLAIN}"
                return 1
                ;;
            *)
                echo -e "${RED}❌ 无效选择。${PLAIN}"
                ;;
        esac
    done
}

entry_mode_expected_listener() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode") || return 1
    case "$mode" in
        "nginx-stream") echo "nginx" ;;
        "xray-fallback") echo "xray" ;;
        "tcp-peek") echo "tcppeek" ;;
    esac
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
    svc=$(xray_entry_service_name) || { echo -e "${RED}❌ 未检测到 xray/x-ui/3x-ui systemd 服务。${PLAIN}"; return 1; }
    systemctl enable "$svc" >/dev/null 2>&1 || true
    systemctl restart "$svc" || { echo -e "${RED}❌ ${svc} 重启失败。${PLAIN}"; return 1; }
}

stop_xray_entry_service_if_public_443() {
    local listener svc
    listener=$(detect_443_listener)
    listener_info_has_entry "$listener" "xray" || return 0
    svc=$(xray_entry_service_name) || return 0
    if ! systemctl stop "$svc"; then
        echo -e "${RED}❌ 停止 ${svc} 失败，公网 443 仍可能被 Xray 占用。${PLAIN}"
        return 1
    fi
    sleep 1
    listener=$(detect_443_listener)
    if listener_info_has_entry "$listener" "xray"; then
        echo -e "${RED}❌ ${svc} 已执行停止，但 Xray 仍在监听公网 443，拒绝继续切换入口。${PLAIN}"
        return 1
    fi
}

stop_vpso_mux_service_if_public_443() {
    local listener
    listener=$(detect_443_listener)
    listener_info_has_entry "$listener" "tcppeek" || return 0
    if ! systemctl stop vpso-mux; then
        echo -e "${RED}❌ 停止 vpso-mux 失败，公网 443 仍可能被 TCP Peek 占用。${PLAIN}"
        print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    sleep 1
    listener=$(detect_443_listener)
    if listener_info_has_entry "$listener" "tcppeek"; then
        echo -e "${RED}❌ vpso-mux 已执行停止，但 TCP Peek 仍在监听公网 443，拒绝继续切换入口。${PLAIN}"
        print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"
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
            echo -e "${RED}❌ Nginx Stream 443 配置已移除，但 nginx 仍在监听公网 443，拒绝继续切换入口。${PLAIN}"
            print_nginx_stream_failure_context "$NGINX_LISTEN_PORT"
            return 1
        fi
        if systemctl is-active --quiet nginx; then
            echo -e "${YELLOW}ℹ️ nginx 服务仍在运行，但已不监听公网 ${NGINX_LISTEN_PORT}；这是允许的，单入口只要求公网 443 由目标入口独占。${PLAIN}"
        fi
    fi
}

stop_public_443_entry_services_for_target() {
    local target_mode="$1"
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1

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
    local action_name="${1:-入口模式切换}"
    local ssh_server_port
    if [[ -z "${SSH_CONNECTION:-}" ]]; then
        return 0
    fi
    ssh_server_port=$(printf '%s\n' "$SSH_CONNECTION" | awk '{print $4}')
    if [[ -n "$ssh_server_port" && "$ssh_server_port" == "${NGINX_LISTEN_PORT:-443}" ]]; then
        echo -e "${RED}❌ 检测到当前 SSH 会话连接在入口端口 ${ssh_server_port}。${PLAIN}"
        echo -e "${YELLOW}${action_name} 会重启或替换该端口的入口服务，继续执行会直接断开当前 SSH。${PLAIN}"
        echo -e "${YELLOW}请改用云厂商 VNC/Serial Console，或先用非 ${ssh_server_port} 的 SSH 端口登录后再执行。${PLAIN}"
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

    echo -e "${RED}❌ 公网 443 监听不符合 ${mode}：期望 ${expected}，实际 ${listener#*|}${PLAIN}"
    return 1
}

print_nginx_stream_failure_context() {
    local port="${1:-$NGINX_LISTEN_PORT}"
    local conf_file="/etc/nginx/stream.d/vps_sni_${port}.conf"
    echo -e "${YELLOW}▶ Nginx Stream 未能稳定监听 ${port}，下面是最近状态和配置线索：${PLAIN}"
    echo -e "${YELLOW}▶ 期望配置文件：${conf_file}${PLAIN}"
    if [[ -s "$conf_file" ]]; then
        sed -n '1,180p' "$conf_file" 2>/dev/null || true
    else
        echo -e "${RED}❌ ${conf_file} 不存在或为空。${PLAIN}"
    fi
    echo -e "${YELLOW}▶ nginx.conf 中的 stream/include 线索：${PLAIN}"
    grep -nE '^[[:space:]]*(stream[[:space:]]*\{|include[[:space:]]+/etc/nginx/stream\.d/\*\.conf;|include[[:space:]]+/etc/nginx/modules-enabled/\*\.conf;)' /etc/nginx/nginx.conf 2>/dev/null || true
    echo -e "${YELLOW}▶ nginx -T 是否加载该 stream 文件：${PLAIN}"
    if nginx -T 2>&1 | grep -Fq "$conf_file"; then
        echo -e "${GREEN}✅ nginx -T 已加载 ${conf_file}${PLAIN}"
    else
        echo -e "${RED}❌ nginx -T 未加载 ${conf_file}${PLAIN}"
    fi
    echo -e "${YELLOW}▶ nginx 服务状态：${PLAIN}"
    systemctl status nginx --no-pager -l 2>/dev/null || true
    echo -e "${YELLOW}▶ 最近 40 行 nginx 日志：${PLAIN}"
    journalctl -u nginx -n 40 --no-pager 2>/dev/null || true
    echo -e "${YELLOW}▶ 当前 ${port} 监听情况：${PLAIN}"
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
        echo -e "${RED}❌ Nginx Stream 配置未生成或为空：${conf_file}${PLAIN}"
        print_nginx_stream_failure_context "$port"
        return 1
    fi
    if ! nginx -T 2>&1 | grep -Fq "$conf_file"; then
        echo -e "${RED}❌ Nginx 主配置没有实际加载 ${conf_file}，拒绝继续。${PLAIN}"
        print_nginx_stream_failure_context "$port"
        return 1
    fi
}

check_entry_mode_dependencies() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode") || { echo -e "${RED}❌ 目标入口模式无效：${mode}${PLAIN}"; return 1; }

    case "$mode" in
        "nginx-stream")
            command -v nginx >/dev/null 2>&1 || echo -e "${YELLOW}未检测到 Nginx，切换时会沿用现有 Nginx stream 安装逻辑。${PLAIN}"
            command -v caddy >/dev/null 2>&1 || echo -e "${YELLOW}未检测到 Caddy，切换时会沿用现有 Caddy 安装逻辑。${PLAIN}"
            ;;
        "tcp-peek")
            require_vpso_mux_binary_for_cutover || return 1
            command -v caddy >/dev/null 2>&1 || echo -e "${YELLOW}未检测到 Caddy，切换时会沿用现有 Caddy 安装逻辑。${PLAIN}"
            ;;
        "xray-fallback")
            xray_entry_service_name >/dev/null 2>&1 || { echo -e "${RED}❌ 未检测到 xray/x-ui/3x-ui systemd 服务，拒绝切换。${PLAIN}"; return 1; }
            command -v caddy >/dev/null 2>&1 || echo -e "${YELLOW}未检测到 Caddy，切换时会沿用现有 Caddy 安装逻辑。${PLAIN}"
            ;;
    esac
}

backup_entry_mode_config() {
    local backup_dir="${1:-}" service_path svc listener_info
    create_sni_stack_backup "$backup_dir" >/dev/null
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    [[ -n "$backup_dir" && -d "$backup_dir" ]] || { echo -e "${RED}❌ 入口模式切换备份失败。${PLAIN}"; return 1; }

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
    echo -e "${YELLOW}▶ 正在停止 vpso-mux 相关服务，避免覆盖运行中的分流器二进制...${PLAIN}"
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
        echo -e "${RED}❌ 未找到可回滚的入口模式备份。${PLAIN}"
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
        confirm_risk_action "回滚上一次 443 入口模式切换" \
            "Nginx/Caddy/Xray/vpso-mux 入口相关配置和服务状态" \
            "再次切换入口模式，或用备份目录手动恢复" \
            "将使用备份目录 ${backup_dir} 覆盖当前入口配置。" || return 1
    fi

    echo -e "${YELLOW}▶ 正在回滚上一次入口模式切换：${backup_dir}${PLAIN}"
    stop_vpso_mux_services_for_restore
    restore_sni_stack_backup_files "$backup_dir" || { echo -e "${RED}❌ 回滚文件恢复失败。${PLAIN}"; return 1; }
    systemctl daemon-reload >/dev/null 2>&1 || true
    load_sni_stack_env >/dev/null 2>&1 || true
    old_mode=${old_mode:-$(get_entry_mode)}

    if ! stop_public_443_entry_services_for_target "$old_mode"; then
        echo -e "${RED}❌ 回滚时未能停止冲突的公网 443 入口服务，请查看上面的诊断。${PLAIN}"
        return 1
    fi
    if ! apply_entry_mode_by_name "$old_mode" "$backup_dir"; then
        echo -e "${RED}❌ 回滚到 ${old_mode} 时未能恢复公网 443 监听，请查看上面的诊断。${PLAIN}"
        return 1
    fi
    set_entry_mode "$old_mode" >/dev/null 2>&1 || true
    write_single_443_engine_state "$(entry_mode_engine_name "$old_mode" 2>/dev/null || echo nginx-stream)" "$backup_dir"
    echo -e "${GREEN}✅ 已回滚到上一次入口模式：${old_mode}${PLAIN}"
}

apply_nginx_stream_mode() {
    local backup_dir="${1:-}"
    install_nginx_stream_stack || return 1
    harden_nginx_public_errors
    apply_caddy_configs_for_single_443 || return 1
    cleanup_old_nginx_sni_stream_configs
    write_nginx_sni_stream_config || return 1
    assert_nginx_stream_config_loaded "$NGINX_LISTEN_PORT" || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    systemctl enable nginx >/dev/null 2>&1 || true
    if ! systemctl restart nginx; then
        print_nginx_stream_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    if ! verify_public_443_listener_for_mode "nginx-stream"; then
        print_nginx_stream_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    probe_tls_sni_certificate "Nginx Stream 面板 SNI" "$(probe_host_for_listen_addr "$NGINX_LISTEN_ADDR")" "$NGINX_LISTEN_PORT" "$PANEL_DOMAIN" || return 1
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    if xray_entry_service_name >/dev/null 2>&1; then
        restart_xray_entry_service || echo -e "${YELLOW}⚠️ Xray/3x-ui 服务重启失败；Nginx Stream/Web 入口已恢复，请单独检查 Xray 入站。${PLAIN}"
    fi
    if ! tcp_probe_host "Xray/REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1; then
        echo -e "${YELLOW}⚠️ Nginx Stream/Web 入口已恢复，但 Xray/REALITY 本地入站未连通。${PLAIN}"
        echo -e "${YELLOW}请在 3x-ui/Xray 确认本地入站正在监听 ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}，或把脚本里的 Xray 本地端口改成实际值。${PLAIN}"
    fi
    write_single_443_engine_state "nginx-stream" "$backup_dir"
}

apply_tcppeek_mode() {
    local backup_dir="${1:-}"
    local tmp_config
    require_vpso_mux_binary_for_cutover || return 1
    warn_if_public_bind "Caddy" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    apply_caddy_configs_for_single_443 || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    tmp_config="/etc/vps-optimize/vpso-mux.yaml.tmp.$$"
    write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$tmp_config" || return 1
    run_vpso_mux_config_check "$tmp_config" || { quarantine_path "$tmp_config" "/etc/vps-optimize/quarantine/vpso-mux" >/dev/null 2>&1 || true; return 1; }
    write_vpso_mux_systemd_service
    mv "$tmp_config" "$(vpso_mux_config_path)" || return 1
    systemctl enable vpso-mux >/dev/null 2>&1 || true
    if ! systemctl restart vpso-mux; then
        print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    if ! verify_public_443_listener_for_mode "tcp-peek"; then
        print_vpso_mux_failure_context "$NGINX_LISTEN_PORT"
        return 1
    fi
    probe_tls_sni_certificate "TCP Peek 面板 SNI" "$(probe_host_for_listen_addr "$NGINX_LISTEN_ADDR")" "$NGINX_LISTEN_PORT" "$PANEL_DOMAIN" || return 1
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    if xray_entry_service_name >/dev/null 2>&1; then
        restart_xray_entry_service || return 1
    fi
    tcp_probe_host "Xray/REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" 6 1 || return 1
    write_single_443_engine_state "tcp-peek" "$backup_dir"
}

apply_xray_fallback_mode() {
    local backup_dir="${1:-}"
    apply_caddy_configs_for_single_443 || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    restart_xray_entry_service || return 1
    verify_public_443_listener_for_mode "xray-fallback" || return 1
    tcp_probe_host "Caddy fallback 后端" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    probe_tls_sni_certificate "Xray Fallback 面板 SNI" "$(probe_host_for_listen_addr "$NGINX_LISTEN_ADDR")" "$NGINX_LISTEN_PORT" "$PANEL_DOMAIN" || return 1
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
    echo -e "${BOLD}选择本次首次配置使用的 443 入口模式${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}  1. Nginx Stream 模式${PLAIN}       ${YELLOW}(默认稳定模式，适合大多数用户)${PLAIN}"
    echo -e "${GREEN}  2. Xray Fallback 模式${PLAIN}      ${YELLOW}(需你已在 Xray/3x-ui 准备好公网 443 主入站)${PLAIN}"
    echo -e "${GREEN}  3. TCP Peek + Splice 模式${PLAIN}  ${YELLOW}(首次安装会先提示安装/使用 Nginx Stream，再跑 8444 预检后切换)${PLAIN}"
    echo -e "${RED}  0. 取消${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    read_trimmed choice "请选择入口模式（默认 1）: "
    case "${choice:-1}" in
        1) ENTRY_MODE="nginx-stream" ;;
        2) ENTRY_MODE="xray-fallback" ;;
        3)
            echo -e "${YELLOW}TCP Peek 首次接管 443 前必须先安装/使用 Nginx Stream，建立可用的共享配置和 Nginx/Caddy 基线。${PLAIN}"
            echo -e "${YELLOW}推荐流程：先安装/使用 Nginx Stream 完成首次安装，再进入 [19] -> [16] 做 8444 预检，最后用 [5] 切换到 TCP Peek。${PLAIN}"
            read_trimmed tcppeek_bootstrap "是否先安装/使用 Nginx Stream 完成本次首次安装？(Y/n，默认 yes): "
            tcppeek_bootstrap="${tcppeek_bootstrap:-yes}"
            if is_yes "$tcppeek_bootstrap"; then
                ENTRY_MODE="nginx-stream"
            else
                echo -e "${BLUE}已取消首次配置。${PLAIN}"
                return 1
            fi
            ;;
        0|q|Q) echo -e "${BLUE}已取消首次配置。${PLAIN}"; return 1 ;;
        *) echo -e "${RED}❌ 无效选择。${PLAIN}"; return 1 ;;
    esac
    echo -e "${GREEN}✅ 已选择 443 入口模式：${ENTRY_MODE}${PLAIN}"
}

prepare_initial_entry_mode_dependencies() {
    local target_mode="$1"
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1
    case "$target_mode" in
        "tcp-peek")
            require_vpso_mux_binary_for_cutover || {
                echo -e "${YELLOW}首次配置阶段尚未有共享配置可用于 8444 预检；请先选择 Nginx Stream 完成首次配置，再运行 [19] -> [16] 预检，最后用 [5] 切换到 TCP Peek。${PLAIN}"
                return 1
            }
            ;;
        "xray-fallback")
            xray_entry_service_name >/dev/null 2>&1 || {
                echo -e "${RED}❌ 未检测到 xray/x-ui/3x-ui systemd 服务，无法首次配置为 xray-fallback。${PLAIN}"
                echo -e "${YELLOW}请先在 [4 面板、节点与订阅工具] 中安装并配置 Xray/3x-ui 主入站，或改选 Nginx Stream 模式 / TCP Peek + Splice 模式。${PLAIN}"
                return 1
            }
            print_xray_fallback_mode_explanation
            confirm_risk_action "首次配置使用 Xray Fallback 模式" \
                "公网 443 将由已有 Xray 主入站接管，普通 HTTPS fallback 到 Caddy" \
                "返回首次配置并选择 Nginx Stream 模式或 TCP Peek + Splice 模式" \
                "确认你已经在 Xray/3x-ui 中准备好公网 443 主入站；脚本不会创建或修改 3x-ui/Xray 入站内部配置。" || return 1
            ;;
    esac
}

switch_entry_mode() {
    local target_mode="$1"
    local current_mode backup_dir planned_backup_dir yn
    load_sni_stack_env || return 1
    target_mode=$(normalize_entry_mode_name "$target_mode") || { echo -e "${RED}❌ 目标入口模式无效：${target_mode}${PLAIN}"; return 1; }
    current_mode=$(get_entry_mode)

    if [[ "$target_mode" == "$current_mode" ]]; then
        read_trimmed yn "当前已经是 ${target_mode}，是否重新应用当前模式？(y/n，默认 n): "
        is_yes "$yn" && reapply_current_entry_mode
        return $?
    fi

    echo -e "${CYAN}准备切换 443 入口模式：${current_mode} -> ${target_mode}${PLAIN}"
    check_entry_mode_dependencies "$target_mode" || return 1
    if [[ "$target_mode" == "xray-fallback" ]]; then
        select_xray_fallback_main_route_for_switch || return 1
    fi
    planned_backup_dir=$(sni_stack_backup_dir)
    preview_entry_mode_cutover "$current_mode" "$target_mode" "$planned_backup_dir" || return 1
    guard_current_ssh_not_on_entry_port "切换 443 入口模式" || return 1
    backup_dir=$(backup_entry_mode_config "$planned_backup_dir") || return 1
    if ! preflight_entry_mode_before_cutover "$target_mode"; then
        echo -e "${RED}❌ 入口模式 ${target_mode} 预检失败，公网 443 未切换。${PLAIN}"
        return 1
    fi

    if ! stop_public_443_entry_services_for_target "$target_mode"; then
        echo -e "${RED}❌ 停止当前公网 443 入口服务失败，正在回滚。${PLAIN}"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi

    if ! apply_entry_mode_by_name "$target_mode" "$backup_dir"; then
        echo -e "${RED}❌ 入口模式 ${target_mode} 应用失败，正在自动回滚。${PLAIN}"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi

    ENTRY_MODE="$target_mode"
    save_sni_stack_env
    write_single_443_engine_state "$(entry_mode_engine_name "$target_mode")" "$backup_dir"
    echo -e "${GREEN}✅ 443 入口模式已切换为：${target_mode}${PLAIN}"
    show_current_entry_status
}

reapply_current_entry_mode() {
    local current_mode backup_dir planned_backup_dir assume_yes
    assume_yes="${1:-}"
    load_sni_stack_env || return 1
    current_mode=$(get_entry_mode)
    current_mode=$(normalize_entry_mode_name "$current_mode") || { echo -e "${RED}❌ 当前 ENTRY_MODE 无效：${current_mode}${PLAIN}"; return 1; }
    echo -e "${CYAN}正在重新应用当前 443 入口模式：${current_mode}${PLAIN}"
    guard_current_ssh_not_on_entry_port "重新应用 443 入口模式" || return 1
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
        echo -e "${RED}❌ 当前入口模式 ${current_mode} 预检失败，公网 443 未重新应用。${PLAIN}"
        return 1
    fi
    if ! stop_public_443_entry_services_for_target "$current_mode"; then
        echo -e "${RED}❌ 停止当前公网 443 入口服务失败，正在回滚。${PLAIN}"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi
    if ! apply_entry_mode_by_name "$current_mode" "$backup_dir"; then
        echo -e "${RED}❌ 当前入口模式重新应用失败，正在自动回滚。${PLAIN}"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi
    ENTRY_MODE="$current_mode"
    save_sni_stack_env
    write_single_443_engine_state "$(entry_mode_engine_name "$current_mode")" "$backup_dir"
    echo -e "${GREEN}✅ 当前入口模式已重新应用：${current_mode}${PLAIN}"
    show_current_entry_status
}

view_vpso_mux_logs() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}📜 vpso-mux 日志${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    journalctl -u vpso-mux -n 120 --no-pager 2>/dev/null || echo "未读取到 vpso-mux 日志。"
}

entry_mode_supports_xray_sni_routes() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode" 2>/dev/null) || return 1
    [[ "$mode" == "nginx-stream" || "$mode" == "tcp-peek" ]]
}
