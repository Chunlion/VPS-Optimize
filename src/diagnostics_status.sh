# shellcheck shell=bash
# Compact service status helpers and system hardware/runtime overview.

service_status_compact() {
    local svc="$1"
    if service_unit_exists "$svc"; then
        if systemctl is-active --quiet "$svc"; then
            printf '%b' "$(localized_text "${GREEN}运行中${PLAIN}" "${GREEN}Running${PLAIN}" "${GREEN}работает${PLAIN}")"
        else
            printf '%b' "$(localized_text "${YELLOW}未运行${PLAIN}" "${YELLOW}Is not running${PLAIN}" "${YELLOW}не работает${PLAIN}")"
        fi
    else
        printf '%b' "$(localized_text "${BLUE}未安装${PLAIN}" "${BLUE}Is not installed${PLAIN}" "${BLUE}не установлен${PLAIN}")"
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
            printf '%b' "$(localized_text "${GREEN}运行中${PLAIN}" "${GREEN}Running${PLAIN}" "${GREEN}работает${PLAIN}")"
        else
            printf '%b' "$(localized_text "${YELLOW}未运行${PLAIN}" "${YELLOW}Is not running${PLAIN}" "${YELLOW}не работает${PLAIN}")"
        fi
    elif xui_panel_installed_by_files; then
        printf '%b' "$(localized_text "${YELLOW}已安装/未运行${PLAIN}" "${YELLOW}Is installed/not running${PLAIN}" "${YELLOW}установлен/не запущен${PLAIN}")"
    else
        printf '%b' "$(localized_text "${BLUE}未安装${PLAIN}" "${BLUE}Is not installed${PLAIN}" "${BLUE}не установлен${PLAIN}")"
    fi
}

xui_panel_state_for_issue() {
    local svc
    if svc=$(xui_panel_service_name); then
        if systemctl is-active --quiet "$svc"; then
            echo "$(localized_text "运行中 (${svc}.service)" "Running (${svc}.service)" "Работает (${svc}.service)")"
        else
            echo "$(localized_text "已安装/未运行 (${svc}.service)" "Installed/not running (${svc}.service)" "Установлен/не запущен (${svc}.service)")"
        fi
    elif xui_panel_installed_by_files; then
        echo "$(localized_text "已安装/未检测到 systemd 服务" "systemd service installed/not detected" "Служба systemd установлена/не обнаружена")"
    else
        echo "$(localized_text "未检测到" "not detected" "не обнаружено")"
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
    echo -e "$(localized_text "${CYAN}🧩 VPS-Optimize 场景概览${PLAIN}" "${CYAN}🧩 VPS-Optimize setup overview${PLAIN}" "${CYAN}🧩 VPS-Optimize Обзор сцены${PLAIN}")"
    echo -e "$(localized_text "脚本版本 : ${GREEN}${SCRIPT_VERSION}${PLAIN}" "Script version: ${GREEN}${SCRIPT_VERSION}${PLAIN}" "Версия скрипта: ${GREEN}${SCRIPT_VERSION}${PLAIN}")"
    echo -e "$(localized_text "关键服务 : nginx[$(service_status_compact nginx)] caddy[$(service_status_compact caddy)] docker[$(service_status_compact docker)] 3x-ui面板[$(xui_panel_status_compact)] Xray内核[$(service_status_compact xray)]" "Key services: nginx[$(service_status_compact nginx)] caddy[$(service_status_compact caddy)] docker[$(service_status_compact docker)] 3x-ui panel[$(xui_panel_status_compact)] Xray core[$(service_status_compact xray)]" "Ключевые сервисы: nginx[$(service_status_compact nginx)] caddy[$(service_status_compact caddy)] docker[$(service_status_compact docker)] Панель 3x-ui[$(xui_panel_status_compact)] Xray core[$(service_status_compact xray)]")"

    if [[ -f /etc/vps-optimize/sni-stack.env ]]; then
        if load_sni_stack_env >/dev/null 2>&1; then
            echo -e "$(localized_text "443 入口 : ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> Caddy ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} / REALITY ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}" "443 Entry: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> Caddy ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} / REALITY ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}" "443 Запись: ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> Caddy ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} / REALITY ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}")"
            echo -e "$(localized_text "3x-ui   : 面板 https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "3x-ui: Panel https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}" "3x-ui: Панель https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}")"
            echo -e "$(localized_text "订阅路径 : 普通 ${SUB_URI_PATH} / Clash-Mihomo ${CLASH_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Subscription path: Normal ${SUB_URI_PATH} / Clash-Mihomo ${CLASH_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}" "Путь подписки: Обычный ${SUB_URI_PATH} / Clash-Mihomo ${CLASH_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}")"
            echo -e "$(localized_text "扩展分流 : 网站/反代 ${#SITE_DOMAINS[@]} 个，TCP/SNI 入站 ${#TCP_ROUTE_SNIS[@]} 个" "Additional routes: ${#SITE_DOMAINS[@]} website/reverse proxy, ${#TCP_ROUTE_SNIS[@]} TCP/SNI inbound" "Дополнительные маршруты: сайты/обратные прокси — ${#SITE_DOMAINS[@]}, входящие TCP/SNI — ${#TCP_ROUTE_SNIS[@]}")"
        else
        echo -e "$(localized_text "443 入口 : ${YELLOW}检测到配置文件，但读取失败，请运行 [19] -> [13] 体检。${PLAIN}" "Port 443 entry: ${YELLOW}configuration found but could not be read; run [19] -> [13] Health check.${PLAIN}" "Точка входа 443: ${YELLOW}конфигурация найдена, но не читается; запустите [19] -> [13] Проверка состояния.${PLAIN}")"
        fi
    else
        echo -e "$(localized_text "443 入口 : ${BLUE}尚未配置；需要面板/订阅/REALITY 共用 443 时进入 [19]。${PLAIN}" "Port 443 entry: ${BLUE}not configured; open [19] to share port 443 between the panel, subscriptions, and REALITY.${PLAIN}" "Точка входа 443: ${BLUE}не настроена; откройте [19], чтобы панель, подписки и REALITY использовали общий порт 443.${PLAIN}")"
    fi

    if command -v docker >/dev/null 2>&1; then
        local running_containers public_binds
        running_containers=$(docker ps -q 2>/dev/null | wc -l | tr -d '[:space:]')
        public_binds=$(docker_public_binding_count)
        echo -e "$(localized_text "Docker   : 运行容器 ${running_containers:-0} 个，公网映射 ${public_binds:-0} 条" "Docker: running containers ${running_containers:-0}, public mapping ${public_binds:-0}" "Docker: запуск контейнеров ${running_containers:-0}, отображение Интернета ${public_binds:-0}")"
    fi

    if declare -F print_traffic_guard_diagnostic_summary >/dev/null; then
        print_traffic_guard_diagnostic_summary 3 no
    fi
}

func_system_info() {
    clear
    local os_name virt_type public_ipv4 public_ipv6
    os_name=$(grep -w "PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
    virt_type=$(systemd-detect-virt 2>/dev/null || true)
    [[ -n "$virt_type" ]] || virt_type="$(localized_text "未知" "Unknown" "Неизвестно")"
    public_ipv4=$(curl -s4 --max-time 3 icanhazip.com || true)
    [[ -n "$public_ipv4" ]] || public_ipv4="$(localized_text "无公网 IPv4" "No public IPv4" "Нет публичного IPv4")"
    public_ipv6=$(curl -s6 --max-time 3 icanhazip.com || true)
    [[ -n "$public_ipv6" ]] || public_ipv6="$(localized_text "无公网 IPv6" "No public IPv6" "Нет публичного IPv6")"
    
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🖥️  本机详细硬件与网络信息大屏${PLAIN}" "${BOLD}🖥️ Large screen with detailed hardware and network information of this machine${PLAIN}" "${BOLD}🖥️ Большой экран с подробной информацией об оборудовании и сети этого устройства${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}系统 OS  :${PLAIN} $os_name ($(uname -m))" "${YELLOW}System OS:${PLAIN} $os_name ($(uname -m))" "Системная ОС ${YELLOW}:${PLAIN} $os_name ($(uname -m))")"
    echo -e "$(localized_text "${YELLOW}内核版本 :${PLAIN} $(uname -r)" "${YELLOW}Kernel version:${PLAIN} $(uname -r)" "Версия ядра ${YELLOW}:${PLAIN} $(uname -r)")"
    echo -e "$(localized_text "${YELLOW}虚拟架构 :${PLAIN} ${virt_type}" "${YELLOW}Virtualization:${PLAIN} ${virt_type}" "${YELLOW}Виртуализация:${PLAIN} ${virt_type}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${YELLOW}CPU 型号 :${PLAIN} $(lscpu | grep "Model name:" | sed 's/Model name:\s*//')" "${YELLOW}CPU Model:${PLAIN} $(lscpu | grep \"Model name:\" | sed 's/Model name:\s*//')" "${YELLOW}Модель процессора:${PLAIN} $(lscpu | grep \"Model name:\" | sed 's/Model name:\s*//')")"
    echo -e "$(localized_text "${YELLOW}CPU 核心 :${PLAIN} $(nproc) 核心" "${YELLOW}CPU core:${PLAIN} $(nproc) core" "Ядро ${YELLOW}ЦП: Ядро${PLAIN} $(nproc)")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${YELLOW}物理内存 :${PLAIN} $(free -h | awk '/^Mem:/ {print $3}') / $(free -h | awk '/^Mem:/ {print $2}')" "${YELLOW}Physical memory:${PLAIN} $(free -h | awk '/^Mem:/ {print $3}') / $(free -h | awk '/^Mem:/ {print $2}')" "Физическая память ${YELLOW}:${PLAIN} $(free -h | awk '/^Mem:/ {print $3}') / $(free -h | awk '/^Mem:/ {print $2}')")"
    echo -e "$(localized_text "${YELLOW}交换内存 :${PLAIN} $(free -h | awk '/^Swap:/ {print $3}') / $(free -h | awk '/^Swap:/ {print $2}')" "${YELLOW}Swap memory:${PLAIN} $(free -h | awk '/^Swap:/ {print $3}') / $(free -h | awk '/^Swap:/ {print $2}')" "Память подкачки ${YELLOW}:${PLAIN} $(free -h | awk '/^Swap:/ {print $3}') / $(free -h | awk '/^Swap:/ {print $2}')")"
    echo -e "$(localized_text "${YELLOW}硬盘空间 :${PLAIN} $(df -h / | awk 'NR==2 {print $3}') / $(df -h / | awk 'NR==2 {print $2}')" "${YELLOW}Hard disk space:${PLAIN} $(df -h / | awk 'NR==2 {print $3}') / $(df -h / | awk 'NR==2 {print $2}')" "Место на жестком диске ${YELLOW}:${PLAIN} $(df -h / | awk 'NR==2 {print $3}') / $(df -h / | awk 'NR==2 {print $2}')")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${YELLOW}IPv4 地址:${PLAIN} ${public_ipv4}" "${YELLOW}IPv4 address:${PLAIN} ${public_ipv4}" "${YELLOW}Адрес IPv4:${PLAIN} ${public_ipv4}")"
    echo -e "$(localized_text "${YELLOW}IPv6 地址:${PLAIN} ${public_ipv6}" "${YELLOW}IPv6 address:${PLAIN} ${public_ipv6}" "${YELLOW}Адрес IPv6:${PLAIN} ${public_ipv6}")"
    echo -e "$(localized_text "${YELLOW}运行时间 :${PLAIN} $(uptime -p | sed 's/up //')" "${YELLOW}Running time:${PLAIN} $(uptime -p | sed 's/up //')" "Время работы ${YELLOW}:${PLAIN} $(uptime -p | sed 's/up //')")"
    echo -e "------------------------------------------------"
    print_project_runtime_overview
    echo -e "${CYAN}================================================${PLAIN}"
    
    read -n 1 -s -r -p "$(localized_text "按任意键返回主菜单..." "Press any key to return to the main menu..." "Нажмите любую клавишу, чтобы вернуться в главное меню...")"
}

# ---------------------------------------------------------
# 12. 综合测试合集
# ---------------------------------------------------------
