# shellcheck shell=bash
# Compact service status helpers and system hardware/runtime overview.

service_status_compact() {
    local svc="$1"
    if service_unit_exists "$svc"; then
        if systemctl is-active --quiet "$svc"; then
            printf '%b' "${GREEN}运行中${PLAIN}"
        else
            printf '%b' "${YELLOW}未运行${PLAIN}"
        fi
    else
        printf '%b' "${BLUE}未安装${PLAIN}"
    fi
}

service_unit_exists() {
    local svc="$1"
    local units
    units=$(systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null || true)
    [[ -n "$units" ]] && return 0
    systemctl status "$svc" >/dev/null 2>&1
}

xui_panel_installed_by_files() {
    command -v 3x-ui >/dev/null 2>&1 && return 0
    command -v x-ui >/dev/null 2>&1 && return 0
    [[ -x /usr/local/x-ui/x-ui ]] && return 0
    [[ -f /etc/x-ui/x-ui.db || -f /usr/local/x-ui/x-ui.db || -f /usr/local/x-ui/bin/x-ui.db ]] && return 0
    return 1
}

xui_panel_service_name() {
    local svc
    for svc in 3x-ui x-ui x-panel; do
        if service_unit_exists "$svc"; then
            printf '%s' "$svc"
            return 0
        fi
    done
    return 1
}

xui_panel_status_compact() {
    local svc
    if svc=$(xui_panel_service_name); then
        if systemctl is-active --quiet "$svc"; then
            printf '%b' "${GREEN}运行中${PLAIN}"
        else
            printf '%b' "${YELLOW}未运行${PLAIN}"
        fi
    elif xui_panel_installed_by_files; then
        printf '%b' "${YELLOW}已安装/未运行${PLAIN}"
    else
        printf '%b' "${BLUE}未安装${PLAIN}"
    fi
}

xui_panel_state_for_issue() {
    local svc
    if svc=$(xui_panel_service_name); then
        if systemctl is-active --quiet "$svc"; then
            echo "运行中 (${svc}.service)"
        else
            echo "已安装/未运行 (${svc}.service)"
        fi
    elif xui_panel_installed_by_files; then
        echo "已安装/未检测到 systemd 服务"
    else
        echo "未检测到"
    fi
}

docker_public_binding_count() {
    local count=0
    local name line ports
    command -v docker >/dev/null 2>&1 || { echo "0"; return 0; }
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        ports=$(docker port "$name" 2>/dev/null || true)
        [[ -z "$ports" ]] && continue
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            docker_port_line_is_public "$line" && count=$((count + 1))
        done <<< "$ports"
    done < <(docker ps --format '{{.Names}}' 2>/dev/null)
    echo "$count"
}

print_project_runtime_overview() {
    echo -e "${CYAN}🧩 VPS-Optimize 场景概览${PLAIN}"
    echo -e "脚本版本 : ${GREEN}${SCRIPT_VERSION}${PLAIN}"
    echo -e "关键服务 : nginx[$(service_status_compact nginx)] caddy[$(service_status_compact caddy)] docker[$(service_status_compact docker)] 3x-ui面板[$(xui_panel_status_compact)] Xray内核[$(service_status_compact xray)]"

    if [[ -f /etc/vps-optimize/sni-stack.env ]]; then
        if load_sni_stack_env >/dev/null 2>&1; then
            echo -e "443 入口 : ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> Caddy ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} / REALITY ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
            echo -e "3x-ui   : 面板 https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
            echo -e "订阅路径 : 普通 ${SUB_URI_PATH} / Clash-Mihomo ${CLASH_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}"
            echo -e "扩展分流 : 网站/反代 ${#SITE_DOMAINS[@]} 个，TCP/SNI 入站 ${#TCP_ROUTE_SNIS[@]} 个"
        else
        echo -e "443 入口 : ${YELLOW}检测到配置文件，但读取失败，请运行 [19] -> [13] 体检。${PLAIN}"
        fi
    else
        echo -e "443 入口 : ${BLUE}尚未配置；需要面板/订阅/REALITY 共用 443 时进入 [19]。${PLAIN}"
    fi

    if command -v docker >/dev/null 2>&1; then
        local running_containers public_binds
        running_containers=$(docker ps -q 2>/dev/null | wc -l | tr -d '[:space:]')
        public_binds=$(docker_public_binding_count)
        echo -e "Docker   : 运行容器 ${running_containers:-0} 个，公网映射 ${public_binds:-0} 条"
    fi

    if declare -F print_traffic_guard_diagnostic_summary >/dev/null; then
        print_traffic_guard_diagnostic_summary 3 no
    fi
}

func_system_info() {
    clear
    local os_name
    os_name=$(grep -w "PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
    
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🖥️  本机详细硬件与网络信息大屏${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}系统 OS  :${PLAIN} $os_name ($(uname -m))"
    echo -e "${YELLOW}内核版本 :${PLAIN} $(uname -r)"
    echo -e "${YELLOW}虚拟架构 :${PLAIN} $(systemd-detect-virt 2>/dev/null || echo "未知")"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}CPU 型号 :${PLAIN} $(lscpu | grep "Model name:" | sed 's/Model name:\s*//')"
    echo -e "${YELLOW}CPU 核心 :${PLAIN} $(nproc) 核心"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}物理内存 :${PLAIN} $(free -h | awk '/^Mem:/ {print $3}') / $(free -h | awk '/^Mem:/ {print $2}')"
    echo -e "${YELLOW}交换内存 :${PLAIN} $(free -h | awk '/^Swap:/ {print $3}') / $(free -h | awk '/^Swap:/ {print $2}')"
    echo -e "${YELLOW}硬盘空间 :${PLAIN} $(df -h / | awk 'NR==2 {print $3}') / $(df -h / | awk 'NR==2 {print $2}')"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}IPv4 地址:${PLAIN} $(curl -s4 --max-time 3 icanhazip.com || echo "无公网IPv4")"
    echo -e "${YELLOW}IPv6 地址:${PLAIN} $(curl -s6 --max-time 3 icanhazip.com || echo "无公网IPv6")"
    echo -e "${YELLOW}运行时间 :${PLAIN} $(uptime -p | sed 's/up //')"
    echo -e "------------------------------------------------"
    print_project_runtime_overview
    echo -e "${CYAN}================================================${PLAIN}"
    
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 12. 综合测试合集
# ---------------------------------------------------------
