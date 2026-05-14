# shellcheck shell=bash
# Network interface overview and operational controls.

network_iface_exists() {
    local iface="$1"
    [[ -n "$iface" && "$iface" != *"/"* && "$iface" != *".."* && -d "/sys/class/net/${iface}" ]]
}

network_default_ifaces() {
    {
        ip -o route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}'
        ip -o -6 route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}'
    } | sort -u
}

network_iface_is_default_route() {
    local iface="$1"
    network_default_ifaces | grep -Fxq "$iface"
}

network_choose_iface() {
    local default_iface iface
    default_iface=$(traffic_guard_detect_iface)
    iface=$(ask_with_default "网卡名称" "${default_iface:-eth0}")
    if ! network_iface_exists "$iface"; then
        echo -e "${RED}❌ 网卡 ${iface} 不存在。${PLAIN}" >&2
        return 1
    fi
    printf '%s' "$iface"
}

network_show_overview() {
    echo -e "${CYAN}--- 网卡地址 ---${PLAIN}"
    ip -br addr 2>/dev/null || ip addr
    echo ""
    echo -e "${CYAN}--- 默认路由 ---${PLAIN}"
    ip route show default 2>/dev/null || true
    ip -6 route show default 2>/dev/null || true
    echo ""
    echo -e "${CYAN}--- DNS ---${PLAIN}"
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl dns 2>/dev/null || cat /etc/resolv.conf 2>/dev/null
    else
        cat /etc/resolv.conf 2>/dev/null || true
    fi
}

network_show_iface_detail() {
    local iface
    iface=$(network_choose_iface) || return 1
    echo -e "${CYAN}--- ${iface} 链路详情 ---${PLAIN}"
    ip -d link show dev "$iface" 2>/dev/null || ip link show dev "$iface"
    echo ""
    echo -e "${CYAN}--- ${iface} 流量统计 ---${PLAIN}"
    ip -s link show dev "$iface" 2>/dev/null || true
    if command -v ethtool >/dev/null 2>&1; then
        echo ""
        echo -e "${CYAN}--- ${iface} 驱动/速率 ---${PLAIN}"
        ethtool "$iface" 2>/dev/null | sed -n '1,40p' || true
    fi
}

network_set_iface_state() {
    local state="$1"
    local iface
    iface=$(network_choose_iface) || return 1
    if [[ "$state" == "down" ]]; then
        local default_hint=""
        if network_iface_is_default_route "$iface"; then
            default_hint="当前网卡承载默认路由，关闭后 SSH 大概率会断开。"
        else
            default_hint="关闭网卡会影响该网卡上的所有连接。"
        fi
        confirm_danger "关闭网卡 ${iface}" \
            "网卡 ${iface} 链路状态" \
            "通过云厂商控制台或本菜单重新启用网卡" \
            "${default_hint}" || return 1
    fi
    ip link set dev "$iface" "$state" || {
        echo -e "${RED}❌ 设置 ${iface} ${state} 失败。${PLAIN}"
        return 1
    }
    echo -e "${GREEN}✅ 已设置 ${iface}: ${state}${PLAIN}"
}

network_set_iface_mtu() {
    local iface mtu
    iface=$(network_choose_iface) || return 1
    read_trimmed mtu "请输入临时 MTU（576-9000，重启后可能恢复）: "
    if ! [[ "$mtu" =~ ^[0-9]+$ ]] || (( 10#$mtu < 576 || 10#$mtu > 9000 )); then
        echo -e "${RED}❌ MTU 无效。${PLAIN}"
        return 1
    fi
    confirm_risk_action "设置 ${iface} MTU 为 ${mtu}" \
        "网卡 ${iface} 的运行时 MTU" \
        "重新设置原 MTU，或重启网络/系统恢复云厂商默认值" \
        "错误 MTU 可能导致部分网站或隧道访问异常。" || return 1
    ip link set dev "$iface" mtu "$mtu" || {
        echo -e "${RED}❌ 设置 MTU 失败。${PLAIN}"
        return 1
    }
    echo -e "${GREEN}✅ ${iface} MTU 已临时设置为 ${mtu}${PLAIN}"
}

network_renew_dhcp() {
    local iface
    iface=$(network_choose_iface) || return 1
    confirm_danger "刷新 ${iface} DHCP 租约" \
        "网卡 ${iface} 的地址租约/网络连接" \
        "通过云厂商控制台重连，或重启系统恢复网络" \
        "如果这是当前 SSH 使用的公网网卡，刷新租约可能短暂断开连接。" || return 1
    if command -v dhclient >/dev/null 2>&1; then
        dhclient -r "$iface" >/dev/null 2>&1 || true
        dhclient "$iface" || return 1
    elif command -v networkctl >/dev/null 2>&1; then
        networkctl renew "$iface" || return 1
    elif command -v nmcli >/dev/null 2>&1; then
        nmcli device reapply "$iface" || nmcli device connect "$iface" || return 1
    else
        echo -e "${YELLOW}⚠️ 未检测到 dhclient/networkctl/nmcli，无法自动刷新 DHCP。${PLAIN}"
        return 1
    fi
    echo -e "${GREEN}✅ 已尝试刷新 ${iface} 的 DHCP/网络连接。${PLAIN}"
}

func_network_interface_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "网络/内核优化 > 网卡管理工具"
        echo -e "${BOLD}🧰 网卡管理工具${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：查看网卡、路由、DNS 和链路状态；危险操作会要求确认。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看网卡 / 路由 / DNS 概览${PLAIN}"
        echo -e "${GREEN}  2. 查看指定网卡详情与流量统计${PLAIN}"
        echo -e "${GREEN}  3. 启用指定网卡${PLAIN}"
        echo -e "${RED}  4. 关闭指定网卡${PLAIN}"
        echo -e "${YELLOW}  5. 临时设置网卡 MTU${PLAIN}"
        echo -e "${YELLOW}  6. 刷新 DHCP/网络连接${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1) network_show_overview; pause_return ;;
            2) network_show_iface_detail; pause_return ;;
            3) network_set_iface_state up; pause_return ;;
            4) network_set_iface_state down; pause_return ;;
            5) network_set_iface_mtu; pause_return ;;
            6) network_renew_dhcp; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 24. 网络加速与内核优化菜单 (二级直达)
# ---------------------------------------------------------
