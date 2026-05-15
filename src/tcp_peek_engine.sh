# shellcheck shell=bash
# 443 entry-mode switching plus vpso-mux TCP Peek engine management.

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
    local caddy_backend xray_backend summary i domain
    caddy_backend=$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    summary="panel:${PANEL_DOMAIN}->${caddy_backend},reality:${REALITY_SNI}->${xray_backend},default->${xray_backend}"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] && summary+=",site:${domain}->${caddy_backend}"
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
    local state_file mux_config mux_service caddy_backend xray_backend routes whitelist_rules
    selected_engine=$(normalize_entry_mode_name "$selected_engine_raw") || { echo -e "${RED}Invalid engine: ${selected_engine_raw}${PLAIN}"; return 1; }
    state_file=$(single_443_engine_state_path)
    mux_config=$(vpso_mux_config_path)
    mux_service=$(vpso_mux_service_name)
    caddy_backend=$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    routes=$(sni_stack_route_summary_for_state)
    whitelist_rules=$(sni_stack_whitelist_summary_for_state)
    [[ -z "$backup_id" ]] && backup_id=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null || true)

    mkdir -p /etc/vps-optimize
    cat <<EOF > "$state_file"
engine='${selected_engine}'
listen_addr='${NGINX_LISTEN_ADDR}'
listen_port='${NGINX_LISTEN_PORT}'
caddy_backend='${caddy_backend}'
xray_backend='${xray_backend}'
default_backend='${xray_backend}'
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
    echo -e "${BOLD}🔎 当前 443 入口状态 / 单入口引擎${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    local engine state_file mux_config
    engine=$(single_443_current_engine)
    state_file=$(single_443_engine_state_path)
    mux_config=$(vpso_mux_config_path)
    show_current_entry_status
    echo -e "------------------------------------------------"
    echo -e "当前 engine：${GREEN}${engine}${PLAIN}"
    echo -e "状态文件：${state_file}"
    echo -e "mux 配置：${mux_config}"
    echo -e "------------------------------------------------"
    echo -e "${GREEN}Nginx Stream 模式是默认稳定模式。${PLAIN}"
    echo -e "${YELLOW}TCP Peek + Splice 模式适合需要四层 SNI 分流和 splice 转发优化的进阶用户。${PLAIN}"
    echo -e "${YELLOW}首次建议先监听 8444 测试，不要直接接管 443。${PLAIN}"
    echo -e "${YELLOW}切换前会自动备份，可回滚。${PLAIN}"
    echo -e "------------------------------------------------"
    if [[ -f /etc/vps-optimize/sni-stack.env ]]; then
        load_sni_stack_env >/dev/null 2>&1 && print_sni_stack_current_summary
    else
        echo -e "${YELLOW}未检测到 sni-stack.env，尚未完成 443 单入口初始化。${PLAIN}"
    fi
    echo -e "------------------------------------------------"
    echo -e "公网 443 监听："
    ss -lntup 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || echo "未监听或当前用户无权限查看进程"
}

show_tcp_peek_splice_info() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}TCP Peek + Splice 模式${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}TCP Peek + Splice 模式：基于 MSG_PEEK 读取 TLS ClientHello 中的 SNI，不消费首包，并根据 SNI 将连接分流到 Caddy 或 Xray 本地后端；转发时优先使用 splice 零拷贝，失败时自动回退普通 copy。实际运行的分流器程序为 vpso-mux。${PLAIN}"
    echo -e "它只在 TCP 层读取 TLS ClientHello 的 SNI，不终止 TLS，不管理证书，不替换 Caddy，也不是 Xray 直占 443。"
    echo -e "推荐流程："
    echo -e "  1. 先生成 TCP Peek + Splice 分流规则：/etc/vps-optimize/vpso-mux.yaml"
    echo -e "  2. 校验配置和后端端口"
    echo -e "  3. 使用 TCP Peek + Splice 测试入口监听 8444"
    echo -e "  4. 确认后再事务式切换公网 443"
    echo -e "  5. 异常时从菜单回滚到 Nginx Stream 模式"
}

print_vpso_mux_systemd_fallback_status() {
    local listen_port="${1:-${NGINX_LISTEN_PORT:-443}}"
    local public_lines preflight_lines
    echo -e "${YELLOW}status.json 不存在或解析失败，已降级为 systemd / 监听状态检查。${PLAIN}"
    echo -e "vpso-mux：$(service_status_compact vpso-mux)"
    echo -e "vpso-mux-preflight：$(service_status_compact vpso-mux-preflight)"
    echo -e "公网 ${listen_port} 监听："
    public_lines=$(ss -lntp 2>/dev/null | awk -v p=":${listen_port}" '$4 ~ p"$" {print}' || true)
    echo "${public_lines:-未监听或当前用户无权限查看进程}"
    echo -e "8444 预检监听："
    preflight_lines=$(ss -lntp 2>/dev/null | awk '$4 ~ ":8444$" {print}' || true)
    echo "${preflight_lines:-未监听或当前用户无权限查看进程}"
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

    "$py_bin" - "$status_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

def value(name, default=0):
    return data.get(name, default)

print(f"status.json：{path}")
print(f"启动时间：{value('start_time', 'unknown')}")
print(f"更新时间：{value('updated_at', 'unknown')}")
listen = data.get("listen_addresses") or []
print("监听地址：" + (", ".join(listen) if listen else "unknown"))
max_connections = value('max_connections', 'unlimited')
if max_connections == 0:
    max_connections = 'unlimited'
print(f"连接上限：{max_connections}")
print(f"当前连接数：{value('active_connections')}")
print(f"连接总数：{value('total_connections')}")
print(f"拒绝连接数：{value('rejected_connections')}")
print(f"后端拨号错误：{value('backend_dial_errors')}")
print(f"splice 成功次数：{value('splice_success')}")
print(f"copy fallback 次数：{value('copy_fallback')}")
print(f"白名单拦截次数：{value('whitelist_blocked')}")
print(f"no_sni 次数：{value('no_sni')}")
print(f"peek 错误次数：{value('peek_errors')}")
print(f"peek 超时次数：{value('peek_timeouts')}")
print(f"客户端->后端字节：{value('bytes_client_to_backend')}")
print(f"后端->客户端字节：{value('bytes_backend_to_client')}")

route_hits = data.get("route_hits") or {}
print("按 route 命中次数：")
if route_hits:
    for name, count in sorted(route_hits.items(), key=lambda item: (-int(item[1]), item[0])):
        print(f"  - {name}: {count}")
else:
    print("  - 暂无")

recent_errors = data.get("recent_errors") or []
print("最近错误：")
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
    print("  - 暂无")
PY
}

show_vpso_mux_runtime_status() {
    local status_file
    status_file=$(vpso_mux_status_json_path)
    echo -e "${BOLD}TCP Peek + Splice 运行统计${PLAIN}"
    if ! print_vpso_mux_status_json; then
        print_vpso_mux_systemd_fallback_status "${NGINX_LISTEN_PORT:-443}"
    fi
    echo -e "------------------------------------------------"
    echo -e "配置文件：$(vpso_mux_config_path)"
    echo -e "systemd：/etc/systemd/system/$(vpso_mux_service_name)"
    echo -e "状态文件：${status_file}"
}

append_vpso_mux_route_yaml() {
    local file="$1"
    local name="$2"
    local sni="$3"
    local backend="$4"
    local whitelist="$5"
    {
        echo "  - name: $(yaml_quote "$name")"
        echo "    sni:"
        echo "      - $(yaml_quote "$sni")"
        echo "    backend: $(yaml_quote "$backend")"
        if [[ -n "$whitelist" ]]; then
            echo "    whitelist:"
            local range
            for range in $whitelist; do
                echo "      - $(yaml_quote "$range")"
            done
        fi
    } >> "$file"
}

write_vpso_mux_config_from_sni_stack() {
    local listen_port="${1:-$NGINX_LISTEN_PORT}"
    local output_file="${2:-$(vpso_mux_config_path)}"
    local caddy_backend xray_backend listen_addr route_name ranges i domain backend
    caddy_backend=$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    mkdir -p "$(dirname "$output_file")"

    {
        echo "listen:"
        echo "  tcp:"
        if [[ "$NGINX_LISTEN_ADDR" == "0.0.0.0" ]]; then
            echo "    - $(yaml_quote "0.0.0.0:${listen_port}")"
        elif [[ "$NGINX_LISTEN_ADDR" == "::" ]]; then
            echo "    - $(yaml_quote "[::]:${listen_port}")"
        else
            listen_addr=$(format_hostport "$NGINX_LISTEN_ADDR" "$listen_port")
            echo "    - $(yaml_quote "$listen_addr")"
        fi
        echo ""
        echo "timeouts:"
        echo "  peek: $(yaml_quote "3s")"
        echo "  dial: $(yaml_quote "5s")"
        echo "  idle: $(yaml_quote "300s")"
        echo "  shutdown: $(yaml_quote "10s")"
        echo ""
        echo "splice:"
        echo "  enabled: true"
        echo "  pipe_size: 1048576"
        echo "  fallback_to_copy: true"
        echo ""
        echo "limits:"
        echo "  max_connections: 4096"
        echo ""
        echo "default_backend: $(yaml_quote "$xray_backend")"
        echo ""
        echo "routes:"
    } > "$output_file"

    ranges=$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")
    append_vpso_mux_route_yaml "$output_file" "panel" "$PANEL_DOMAIN" "$caddy_backend" "$ranges"
    if [[ -z "$ranges" ]]; then
        echo -e "${YELLOW}⚠️ 面板域名 ${PANEL_DOMAIN} 当前未配置 IP 白名单；切换前请确认这是你想要的行为。${PLAIN}"
    fi

    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        route_name=$(sni_stack_route_name "site" "$domain")
        ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        append_vpso_mux_route_yaml "$output_file" "$route_name" "$domain" "$caddy_backend" "$ranges"
    done

    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        route_name=$(sni_stack_route_name "tcp" "$domain")
        backend=$(format_hostport "${TCP_ROUTE_ADDRS[$i]}" "${TCP_ROUTE_PORTS[$i]}")
        append_vpso_mux_route_yaml "$output_file" "$route_name" "$domain" "$backend" ""
    done

    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        route_name=$(sni_stack_route_name "xray" "$domain")
        backend=$(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}")
        append_vpso_mux_route_yaml "$output_file" "$route_name" "$domain" "$backend" ""
    done

    append_vpso_mux_route_yaml "$output_file" "reality" "$REALITY_SNI" "$xray_backend" ""

    cat <<EOF >> "$output_file"

logging:
  level: $(yaml_quote "info")
  format: $(yaml_quote "json")
EOF
    chmod 600 "$output_file" 2>/dev/null || true
}

generate_tcp_peek_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}重新应用 TCP Peek + Splice 配置${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}只生成 TCP Peek + Splice 分流规则，不改服务，不改端口，不接管 443。${PLAIN}"
    write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$(vpso_mux_config_path)" || return 1
    echo -e "${GREEN}✅ 已生成：$(vpso_mux_config_path)${PLAIN}"
    echo -e "默认后端：$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")"
    echo -e "Caddy 后端：$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")"
    echo -e "${YELLOW}下一步建议先校验配置，再使用 TCP Peek + Splice 测试入口监听 8444。${PLAIN}"
}

go_install_vpso_mux_latest() {
    local module_version tmp_dir
    echo -e "${CYAN}▶ 正在使用本机 Go 以兼容模式构建 vpso-mux...${PLAIN}"
    if ! go version 2>/dev/null | grep -Eq 'go1\.(2[2-9]|[3-9][0-9])'; then
        echo -e "${RED}❌ 当前 Go 版本低于 1.22，拒绝在生产机上自动下载临时 Go 工具链。${PLAIN}"
        echo -e "${YELLOW}请先通过系统包管理器安装 Go 1.22+，或在安全环境构建 /usr/local/bin/vpso-mux 后再切换 TCP Peek。${PLAIN}"
        return 1
    fi
    vpso_mux_build_resource_check || return 1
    module_version=$(GOTOOLCHAIN=local go list -m -f '{{.Version}}' github.com/Chunlion/VPS-Optimize@latest 2>/dev/null) || return 1
    tmp_dir=$(mktemp -d /tmp/vpso-mux-build.XXXXXX) || return 1
    cat <<EOF > "${tmp_dir}/go.mod"
module vpso-mux-build

go 1.22

require github.com/Chunlion/VPS-Optimize ${module_version}

replace golang.org/x/sys => golang.org/x/sys v0.30.0
EOF
    (
        local mod_dir patched_dir patch_file
        cd "$tmp_dir" || exit 1
        GOMAXPROCS=1 GOTOOLCHAIN=local go mod download github.com/Chunlion/VPS-Optimize || exit 1
        mod_dir=$(GOTOOLCHAIN=local go list -m -f '{{.Dir}}' github.com/Chunlion/VPS-Optimize) || exit 1
        patched_dir="${tmp_dir}/VPS-Optimize-src"
        cp -a "$mod_dir" "$patched_dir" || exit 1
        chmod -R u+w "$patched_dir" 2>/dev/null || true
        patch_file="${patched_dir}/cmd/vpso-mux/main.go"
        if grep -q 'unix\.Splice(pipeFD\[0\], nil, dstFD, nil, remaining,' "$patch_file" 2>/dev/null; then
            echo -e "${YELLOW}⚠️ 检测到远程 vpso-mux 旧源码，正在应用 Go 兼容修补...${PLAIN}"
            sed -i 's/unix\.Splice(pipeFD\[0\], nil, dstFD, nil, remaining,/unix.Splice(pipeFD[0], nil, dstFD, nil, int(remaining),/' "$patch_file" || exit 1
        fi
        cat <<EOF >> "${tmp_dir}/go.mod"

replace github.com/Chunlion/VPS-Optimize => ./VPS-Optimize-src
EOF
        GOMAXPROCS=1 GOTOOLCHAIN=local go get "github.com/Chunlion/VPS-Optimize/cmd/vpso-mux@${module_version}" || exit 1
        GOMAXPROCS=1 GOTOOLCHAIN=local go build -p 1 -o /usr/local/bin/vpso-mux github.com/Chunlion/VPS-Optimize/cmd/vpso-mux
    )
}

vpso_mux_build_resource_check() {
    local mem_kb swap_kb available_kb tmp_kb
    if [[ -r /proc/meminfo ]]; then
        mem_kb=$(awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
        swap_kb=$(awk '/SwapFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
        mem_kb=${mem_kb:-0}
        swap_kb=${swap_kb:-0}
        available_kb=$((mem_kb + swap_kb))
        if (( available_kb > 0 && available_kb < 262144 )); then
            echo -e "${RED}❌ 可用内存+Swap 低于 256MB，拒绝在当前服务器上编译 vpso-mux，避免系统失联。${PLAIN}"
            return 1
        fi
    fi
    tmp_kb=$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    tmp_kb=${tmp_kb:-0}
    if (( tmp_kb > 0 && tmp_kb < 524288 )); then
        echo -e "${RED}❌ /tmp 可用空间低于 512MB，拒绝构建 vpso-mux。${PLAIN}"
        return 1
    fi
}

require_vpso_mux_binary_for_cutover() {
    if [[ -x /usr/local/bin/vpso-mux ]]; then
        return 0
    fi
    echo -e "${RED}❌ 缺少 /usr/local/bin/vpso-mux，拒绝切换到 TCP Peek + Splice 模式。${PLAIN}"
    echo -e "${YELLOW}为避免生产机在 443 切换过程中下载 Go 工具链或远端编译，公网 443 切换流程不会自动构建 vpso-mux。${PLAIN}"
    echo -e "${YELLOW}请先在 443 管理中心运行 TCP Peek 8444 预检/测试，确认 vpso-mux 安装和测试端口都正常后，再切换公网 443。${PLAIN}"
    return 1
}

install_vpso_mux_binary() {
    if [[ -x /usr/local/bin/vpso-mux ]]; then
        return 0
    fi

    if ! command -v go >/dev/null 2>&1; then
        echo -e "${CYAN}▶ 未检测到 Go，正在安装 vpso-mux 构建工具链...${PLAIN}"
        if is_debian; then
            install_pkg golang-go || install_pkg golang || return 1
        elif is_redhat; then
            install_pkg golang || return 1
        else
            echo -e "${RED}❌ 当前系统暂不支持自动安装 Go，请先安装 Go 1.22+ 后重试。${PLAIN}"
            return 1
        fi
    fi

    command -v go >/dev/null 2>&1 || { echo -e "${RED}❌ Go 安装后仍不可用，无法构建 vpso-mux。${PLAIN}"; return 1; }

    local source_dir="${SCRIPT_DIR:-$(pwd)}"
    if [[ -d "$source_dir/cmd/vpso-mux" ]]; then
        echo -e "${CYAN}▶ 正在从当前源码构建 vpso-mux...${PLAIN}"
        (cd "$source_dir" && go build -o /usr/local/bin/vpso-mux ./cmd/vpso-mux) || return 1
        chmod 755 /usr/local/bin/vpso-mux
        return 0
    fi

    go_install_vpso_mux_latest || return 1
    chmod 755 /usr/local/bin/vpso-mux 2>/dev/null || true
    [[ -x /usr/local/bin/vpso-mux ]] || { echo -e "${RED}❌ vpso-mux 安装后仍不可执行：/usr/local/bin/vpso-mux${PLAIN}"; return 1; }
    return 0
}

write_vpso_mux_systemd_service() {
    local service_file="${1:-/etc/systemd/system/vpso-mux.service}"
    cat <<'EOF' > "$service_file"
[Unit]
Description=VPS-Optimize TCP Peek + Splice vpso-mux router
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vpso-mux -config /etc/vps-optimize/vpso-mux.yaml
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
    chmod 644 "$service_file"
    if [[ "$service_file" == "/etc/systemd/system/vpso-mux.service" ]]; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

run_vpso_mux_config_check() {
    local config_file="${1:-$(vpso_mux_config_path)}"
    if [[ -x /usr/local/bin/vpso-mux ]]; then
        /usr/local/bin/vpso-mux -config "$config_file" -check
        return $?
    fi
    local source_dir="${SCRIPT_DIR:-$(pwd)}"
    if command -v go >/dev/null 2>&1 && [[ -d "$source_dir/cmd/vpso-mux" ]]; then
        (cd "$source_dir" && go run ./cmd/vpso-mux -config "$config_file" -check)
        return $?
    fi
    echo -e "${RED}❌ 缺少 vpso-mux 二进制或 Go 工具链，无法执行完整配置校验。${PLAIN}"
    return 1
}

print_vpso_mux_failure_context() {
    local port="${1:-$NGINX_LISTEN_PORT}"
    echo -e "${YELLOW}▶ vpso-mux 未能稳定监听 ${port}，下面是最近状态和日志：${PLAIN}"
    systemctl status vpso-mux --no-pager -l 2>/dev/null || true
    echo -e "${YELLOW}▶ 最近 40 行 vpso-mux 日志：${PLAIN}"
    journalctl -u vpso-mux -n 40 --no-pager 2>/dev/null || true
    echo -e "${YELLOW}▶ 当前 ${port} 监听情况：${PLAIN}"
    if command -v ss >/dev/null 2>&1; then
        ss -lntp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print}' || true
    else
        netstat -lntp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print}' || true
    fi
}

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
    ensure_caddy_local_base_config || return 1
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
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
    ensure_caddy_local_base_config || return 1
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
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
        case "${choice:-0}" in
            1|d|D|diff)
                show_entry_mode_cutover_diff "$target_mode"
                ;;
            2|y|Y|yes|YES)
                return 0
                ;;
            0|n|N|no|NO|q|Q)
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
    ensure_caddy_local_base_config || return 1
    cleanup_old_nginx_sni_stream_configs
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
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
    ensure_caddy_local_base_config || return 1
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
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
    ensure_caddy_local_base_config || return 1
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
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
    local choice
    ENTRY_MODE="nginx-stream"

    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}选择本次首次配置使用的 443 入口模式${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}  1. Nginx Stream 模式${PLAIN}       ${YELLOW}(默认稳定模式，适合大多数用户)${PLAIN}"
    echo -e "${GREEN}  2. Xray Fallback 模式${PLAIN}      ${YELLOW}(需你已在 Xray/3x-ui 准备好公网 443 主入站)${PLAIN}"
    echo -e "${GREEN}  3. TCP Peek + Splice 模式${PLAIN}  ${YELLOW}(需已有 vpso-mux；新机器建议先选 Nginx Stream，再跑 8444 预检后切换)${PLAIN}"
    echo -e "${RED}  0. 取消${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    read_trimmed choice "请选择入口模式（默认 1）: "
    case "${choice:-1}" in
        1) ENTRY_MODE="nginx-stream" ;;
        2) ENTRY_MODE="xray-fallback" ;;
        3) ENTRY_MODE="tcp-peek" ;;
        0) echo -e "${BLUE}已取消首次配置。${PLAIN}"; return 1 ;;
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
        [[ "$yn" =~ ^[Yy]$ ]] && reapply_current_entry_mode
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
