# shellcheck shell=bash
# Deployment preflight checks and issue diagnostic bundle generation.

preflight_install_missing_commands() {
    local missing=("$@")
    local pkgs=()
    local cmd

    for cmd in "${missing[@]}"; do
        case "$cmd" in
            curl) pkgs+=("curl") ;;
            wget) pkgs+=("wget") ;;
            ss)
                if is_debian; then
                    pkgs+=("iproute2")
                elif is_redhat; then
                    pkgs+=("iproute")
                fi
                ;;
        esac
    done

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        return 0
    fi

    echo -e "${CYAN}▶ 正在安装缺失基础命令: ${missing[*]}${PLAIN}"
    install_pkg "${pkgs[@]}"
}

preflight_missing_minimal_compat_items() {
    local missing=()
    local cmd svc
    local commands=(curl wget ss ip getent tar gzip openssl jq awk sed grep pgrep journalctl timedatectl)
    local services=()

    for cmd in "${commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("cmd:$cmd")
    done

    if is_debian; then
        services=(cron dbus chrony)
    elif is_redhat; then
        services=(crond dbus chronyd)
    fi

    for svc in "${services[@]}"; do
        systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | awk 'NF {found=1} END {exit found ? 0 : 1}' || missing+=("svc:$svc")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf '%s\n' "${missing[@]}"
    fi
}

preflight_enable_ntp() {
    local ntp_sync
    echo -e "${CYAN}▶ 正在尝试开启系统 NTP 时间同步...${PLAIN}"

    if is_debian; then
        install_pkg chrony
    elif is_redhat; then
        install_pkg chrony
    fi

    timedatectl set-ntp true >/dev/null 2>&1 || true
    systemctl enable --now chrony >/dev/null 2>&1 || true
    systemctl enable --now chronyd >/dev/null 2>&1 || true

    if command -v chronyc >/dev/null 2>&1; then
        chronyc -a 'burst 4/4' >/dev/null 2>&1 || true
        chronyc -a makestep >/dev/null 2>&1 || true
    else
        systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
    fi

    sleep 2
    ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [[ "$ntp_sync" == "yes" ]]; then
        echo -e "${GREEN}✅ NTP 时间同步已恢复。${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ NTP 仍未同步，下面是诊断信息：${PLAIN}"
        timedatectl status 2>/dev/null || true
        chronyc tracking 2>/dev/null || true
        chronyc sources -v 2>/dev/null || true
        journalctl -u chrony -u chronyd -u systemd-timesyncd -n 20 --no-pager 2>/dev/null || true
    fi
}

func_preflight_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧪 一键运维预检 (网络/系统/资源/包管理/精简系统兼容)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local ok_count=0
    local warn_count=0
    local err_count=0

    echo -e "${YELLOW}▶ [1/8] 检查系统运行状态...${PLAIN}"
    local sys_state
    sys_state=$(systemctl is-system-running 2>/dev/null)
    sys_state=${sys_state:-unknown}
    if [[ "$sys_state" == "running" ]]; then
        echo -e "${GREEN}✅ systemd 状态正常: $sys_state${PLAIN}"
        ((ok_count++))
    elif [[ "$sys_state" == "degraded" ]]; then
        echo -e "${YELLOW}⚠️ systemd 状态降级: $sys_state${PLAIN}"
        systemctl --failed --no-legend --no-pager 2>/dev/null | awk 'NF {print "   - " $1 " (" $2 ")"}' | head -n 8
        ((warn_count++))
    else
        echo -e "${RED}❌ systemd 状态异常: $sys_state${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [2/8] 检查公网连通性...${PLAIN}"
    local ipv4
    ipv4=$(curl -s4 --max-time 3 icanhazip.com 2>/dev/null)
    if [[ -n "$ipv4" ]]; then
        echo -e "${GREEN}✅ IPv4 连通正常: ${ipv4}${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ 未检测到公网 IPv4，可能为纯 IPv6 或网络受限${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [3/8] 检查 DNS 解析能力...${PLAIN}"
    if getent ahosts raw.githubusercontent.com >/dev/null 2>&1; then
        echo -e "${GREEN}✅ DNS 解析正常 (raw.githubusercontent.com)${PLAIN}"
        ((ok_count++))
    else
        echo -e "${RED}❌ DNS 解析失败，后续远程脚本可能无法下载${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [4/8] 检查时间同步状态...${PLAIN}"
    local ntp_sync
    local can_fix_ntp=false
    ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [[ "$ntp_sync" == "yes" ]]; then
        echo -e "${GREEN}✅ NTP 时间同步正常${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ NTP 未同步，可能影响证书签发与仓库校验${PLAIN}"
        can_fix_ntp=true
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [5/8] 检查磁盘空间...${PLAIN}"
    local root_use
    root_use=$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}')
    if [[ -n "$root_use" && "$root_use" -lt 80 ]]; then
        echo -e "${GREEN}✅ 根分区使用率健康: ${root_use}%${PLAIN}"
        ((ok_count++))
    elif [[ -n "$root_use" && "$root_use" -lt 90 ]]; then
        echo -e "${YELLOW}⚠️ 根分区使用率偏高: ${root_use}%${PLAIN}"
        ((warn_count++))
    else
        echo -e "${RED}❌ 根分区使用率危险: ${root_use:-未知}%${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [6/8] 检查可用内存...${PLAIN}"
    local mem_avail
    mem_avail=$(free -m | awk '/^Mem:/ {print $7}')
    [[ -z "$mem_avail" ]] && mem_avail=$(free -m | awk '/^Mem:/ {print $4}')
    if [[ -n "$mem_avail" && "$mem_avail" -ge 300 ]]; then
        echo -e "${GREEN}✅ 可用内存充足: ${mem_avail}MB${PLAIN}"
        ((ok_count++))
    elif [[ -n "$mem_avail" && "$mem_avail" -ge 150 ]]; then
        echo -e "${YELLOW}⚠️ 可用内存偏低: ${mem_avail}MB${PLAIN}"
        ((warn_count++))
    else
        echo -e "${RED}❌ 可用内存过低: ${mem_avail:-未知}MB${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [7/8] 检查包管理器占用...${PLAIN}"
    local pkg_busy=false
    if is_debian; then
        pgrep -x apt >/dev/null 2>&1 && pkg_busy=true
        pgrep -x apt-get >/dev/null 2>&1 && pkg_busy=true
        pgrep -x dpkg >/dev/null 2>&1 && pkg_busy=true
    elif is_redhat; then
        pgrep -x yum >/dev/null 2>&1 && pkg_busy=true
        pgrep -x dnf >/dev/null 2>&1 && pkg_busy=true
        pgrep -x rpm >/dev/null 2>&1 && pkg_busy=true
    fi

    if $pkg_busy; then
        echo -e "${YELLOW}⚠️ 检测到包管理器正在运行，建议稍后再安装软件${PLAIN}"
        ((warn_count++))
    else
        echo -e "${GREEN}✅ 包管理器空闲，可安全执行安装任务${PLAIN}"
        ((ok_count++))
    fi

    echo -e "${YELLOW}▶ [8/9] 检查关键命令可用性...${PLAIN}"
    local cmd_miss=()
    command -v curl >/dev/null 2>&1 || cmd_miss+=("curl")
    command -v wget >/dev/null 2>&1 || cmd_miss+=("wget")
    command -v ss >/dev/null 2>&1 || cmd_miss+=("ss")
    if [[ ${#cmd_miss[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ 关键命令齐全${PLAIN}"
        ((ok_count++))
    else
        echo -e "${RED}❌ 缺少关键命令: ${cmd_miss[*]}${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [9/9] 检查精简系统兼容组件...${PLAIN}"
    local minimal_miss=()
    mapfile -t minimal_miss < <(preflight_missing_minimal_compat_items)
    if [[ ${#minimal_miss[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ 精简系统兼容组件齐全${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ 检测到精简系统缺少组件/服务:${PLAIN}"
        printf '  - %s\n' "${minimal_miss[@]}"
        ((warn_count++))
    fi

    echo -e "------------------------------------------------"
    echo -e "${CYAN}📌 预检汇总: ${GREEN}${ok_count} 正常${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${err_count} 异常${PLAIN}"
    if [[ "$err_count" -gt 0 ]]; then
        echo -e "${RED}⚠️ 建议先修复异常项，再进行环境部署和系统改造。${PLAIN}"
    elif [[ "$warn_count" -gt 0 ]]; then
        echo -e "${YELLOW}💡 当前可继续操作，但建议先处理警告项以提升稳定性。${PLAIN}"
    else
        echo -e "${GREEN}🎉 当前环境健康，可直接进行后续部署。${PLAIN}"
    fi

    if ! $pkg_busy && { $can_fix_ntp || [[ ${#cmd_miss[@]} -gt 0 ]] || [[ ${#minimal_miss[@]} -gt 0 ]]; }; then
        local fix_confirm rerun_confirm
        echo -e "------------------------------------------------"
        echo -e "${CYAN}🛠️ 可自动处理的简单问题:${PLAIN}"
        $can_fix_ntp && echo -e "  - 开启 NTP 时间同步"
        [[ ${#cmd_miss[@]} -gt 0 ]] && echo -e "  - 安装缺失基础命令: ${cmd_miss[*]}"
        [[ ${#minimal_miss[@]} -gt 0 ]] && echo -e "  - 补齐精简系统兼容组件"
        read_trimmed fix_confirm "是否现在自动修复这些简单问题？(y/N): "
        if is_yes "$fix_confirm"; then
            [[ ${#minimal_miss[@]} -gt 0 ]] && ensure_minimal_system_compat
            $can_fix_ntp && preflight_enable_ntp
            [[ ${#cmd_miss[@]} -gt 0 ]] && preflight_install_missing_commands "${cmd_miss[@]}"
            echo -e "${GREEN}✅ 简单修复已执行。${PLAIN}"
            read_trimmed rerun_confirm "是否立即重新体检？(y/N): "
            if is_yes "$rerun_confirm"; then
                func_preflight_check
                return
            fi
        fi
    elif $pkg_busy; then
        echo -e "${YELLOW}ℹ️ 包管理器正在运行，本次跳过自动安装类修复。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 21. 配置备份与回滚中心
# ---------------------------------------------------------







# ---------------------------------------------------------
# 22. 服务健康总览
# ---------------------------------------------------------
service_state_for_issue() {
    local svc="$1"
    if service_unit_exists "$svc"; then
        if systemctl is-active --quiet "$svc"; then
            echo "运行中"
        else
            echo "已安装/未运行"
        fi
    else
        echo "未检测到"
    fi
}

recent_journal_for_issue() {
    local svc="$1"
    if service_unit_exists "$svc"; then
        journalctl -u "$svc" -n 8 --no-pager 2>/dev/null | redact_sensitive_output
    else
        echo "未检测到 ${svc} 服务"
    fi
}

generate_issue_diagnostics() {
    local os_desc kernel arch now script_path firewall_status latest_backups log_path
    os_desc="未知"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_desc="${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-}}"
    fi
    kernel=$(uname -r 2>/dev/null || echo "未知")
    arch=$(uname -m 2>/dev/null || echo "未知")
    now=$(date -Is 2>/dev/null || date)
    script_path=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")

    if command -v ufw >/dev/null 2>&1; then
        firewall_status=$(ufw status 2>/dev/null | head -n 5 | tr '\n' '; ')
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall_status=$(firewall-cmd --state 2>/dev/null || echo "firewalld 未运行")
    else
        firewall_status="未检测到 ufw/firewalld"
    fi

    latest_backups=$(find /etc/vps-optimize/backups -maxdepth 3 -type f -o -type d 2>/dev/null | sort -r | head -n 10)
    [[ -z "$latest_backups" ]] && latest_backups="未检测到"

    log_path=$(find /var/log /tmp /etc/vps-optimize -maxdepth 3 -type f \( -iname '*vps*optimize*.log' -o -iname '*cy*.log' \) 2>/dev/null | sort -r | head -n 5)
    [[ -z "$log_path" ]] && log_path="未检测到"

    echo ""
    echo "===== VPS-Optimize 反馈诊断信息 ====="
    echo "系统版本: ${os_desc}"
    echo "内核版本: ${kernel}"
    echo "CPU 架构: ${arch}"
    echo "脚本版本: ${SCRIPT_VERSION}"
    echo "脚本路径: ${script_path}"
    echo "当前时间: ${now}"
    echo ""
    echo "关键服务状态:"
    for svc in nginx caddy docker xray sing-box; do
        echo "- ${svc}: $(service_state_for_issue "$svc")"
    done
    echo "- 3x-ui 面板: $(xui_panel_state_for_issue)"
    echo ""
    echo "监听端口摘要:"
    ss -tulnp 2>/dev/null | sed -E 's/users:\(\("[^"]+",pid=[0-9]+,fd=[0-9]+\)\)/users:(process-redacted)/g' | head -n 30 || echo "未检测到 ss 输出"
    echo ""
    echo "443 占用情况:"
    ss -tulnp 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || echo "未检测到 443 监听"
    echo ""
    echo "防火墙状态:"
    echo "${firewall_status}"
    echo ""
    echo "最近 Nginx 错误日志摘要:"
    recent_journal_for_issue nginx
    echo ""
    echo "最近 Caddy 错误日志摘要:"
    recent_journal_for_issue caddy
    echo ""
    echo "最近脚本日志路径:"
    echo "${log_path}"
    echo ""
    echo "最近备份列表:"
    echo "${latest_backups}"
    echo "===== 诊断信息结束，请提交前再次检查是否有敏感信息 ====="
}
