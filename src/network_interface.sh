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
    iface=$(ask_with_default "$(localized_text "网卡名称" "Network card name" "Имя сетевой карты")" "${default_iface:-eth0}")
    if ! network_iface_exists "$iface"; then
        echo -e "$(localized_text "${RED}❌ 网卡 ${iface} 不存在。${PLAIN}" "${RED}❌ Network card ${iface} does not exist.${PLAIN}" "${RED}❌ Сетевая карта ${iface} не существует.${PLAIN}")" >&2
        return 1
    fi
    printf '%s' "$iface"
}

network_show_overview() {
    echo -e "$(localized_text "${CYAN}--- 网卡地址 ---${PLAIN}" "${CYAN}---Network card address ---${PLAIN}" "${CYAN}--- Адрес сетевой карты ---${PLAIN}")"
    ip -br addr 2>/dev/null || ip addr
    echo ""
    echo -e "$(localized_text "${CYAN}--- 默认路由 ---${PLAIN}" "${CYAN}---Default route ---${PLAIN}" "${CYAN}--- Маршрут по умолчанию ---${PLAIN}")"
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
    echo -e "$(localized_text "${CYAN}--- ${iface} 链路详情 ---${PLAIN}" "${CYAN}---${iface} Link details---${PLAIN}" "${CYAN}--- ${iface} Подробности ссылки ---${PLAIN}")"
    ip -d link show dev "$iface" 2>/dev/null || ip link show dev "$iface"
    echo ""
    echo -e "$(localized_text "${CYAN}--- ${iface} 流量统计 ---${PLAIN}" "${CYAN}---${iface} Traffic statistics---${PLAIN}" "${CYAN}---${iface} Статистика трафика---${PLAIN}")"
    ip -s link show dev "$iface" 2>/dev/null || true
    if command -v ethtool >/dev/null 2>&1; then
        echo ""
        echo -e "$(localized_text "${CYAN}--- ${iface} 驱动/速率 ---${PLAIN}" "${CYAN}---${iface} drive/rate---${PLAIN}" "${CYAN}--- ${iface} привод/скорость ---${PLAIN}")"
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
            default_hint="$(localized_text "当前网卡承载默认路由，关闭后 SSH 大概率会断开。" "The current network card carries the default route, and SSH will most likely be disconnected after it is closed." "Текущая сетевая карта использует маршрут по умолчанию, и SSH, скорее всего, будет отключен после закрытия.")"
        else
            default_hint="$(localized_text "关闭网卡会影响该网卡上的所有连接。" "Shutting down a network card affects all connections on that network card." "Выключение сетевой карты влияет на все соединения на этой сетевой карте.")"
        fi
        confirm_danger "$(localized_text "关闭网卡 ${iface}" "Turn off the network card ${iface}" "Выключите сетевую карту ${iface}")" \
            "$(localized_text "网卡 ${iface} 链路状态" "Network card ${iface} link status" "Статус соединения сетевой карты ${iface}")" \
            "$(localized_text "通过云厂商控制台或本菜单重新启用网卡" "Re-enable the network card through the cloud vendor console or this menu" "Повторно включите сетевую карту через консоль поставщика облака или это меню.")" \
            "${default_hint}" || return 1
    fi
    ip link set dev "$iface" "$state" || {
        echo -e "$(localized_text "${RED}❌ 设置 ${iface} ${state} 失败。${PLAIN}" "${RED}❌ Setting ${iface} ${state} failed.${PLAIN}" "${RED}❌ Настройка ${iface} ${state} не удалась.${PLAIN}")"
        return 1
    }
    echo -e "$(localized_text "${GREEN}✅ 已设置 ${iface}: ${state}${PLAIN}" "${GREEN}✅ Already set ${iface}: ${state}${PLAIN}" "${GREEN}✅ Уже установлен ${iface}: ${state}${PLAIN}")"
}

network_set_iface_mtu() {
    local iface mtu
    iface=$(network_choose_iface) || return 1
    read_trimmed mtu "$(localized_text "请输入临时 MTU（576-9000，重启后可能恢复）: " "Please enter temporary MTU (576-9000, may be restored after reboot):" "Пожалуйста, введите временный MTU (576-9000, может быть восстановлен после перезагрузки):")"
    if ! [[ "$mtu" =~ ^[0-9]+$ ]] || (( 10#$mtu < 576 || 10#$mtu > 9000 )); then
        echo -e "$(localized_text "${RED}❌ MTU 无效。${PLAIN}" "${RED}❌ MTU is invalid.${PLAIN}" "${RED}❌ Неверный MTU.${PLAIN}")"
        return 1
    fi
    confirm_risk_action "$(localized_text "设置 ${iface} MTU 为 ${mtu}" "Set ${iface} MTU to ${mtu}" "Установите для ${iface} MTU значение ${mtu}.")" \
        "$(localized_text "网卡 ${iface} 的运行时 MTU" "Runtime MTU of network card ${iface}" "MTU времени выполнения сетевой карты ${iface}")" \
        "$(localized_text "重新设置原 MTU，或重启网络/系统恢复云厂商默认值" "Reset the original MTU, or restart the network/system to restore the cloud vendor's default value." "Сбросьте исходное значение MTU или перезапустите сеть/систему, чтобы восстановить значение по умолчанию, установленное поставщиком облака.")" \
        "$(localized_text "错误 MTU 可能导致部分网站或隧道访问异常。" "Wrong MTU may cause abnormal access to some websites or tunnels." "Неправильный MTU может привести к ненормальному доступу к некоторым веб-сайтам или туннелям.")" || return 1
    ip link set dev "$iface" mtu "$mtu" || {
        echo -e "$(localized_text "${RED}❌ 设置 MTU 失败。${PLAIN}" "${RED}❌ Failed to set MTU.${PLAIN}" "${RED}❌ Не удалось установить MTU.${PLAIN}")"
        return 1
    }
    echo -e "$(localized_text "${GREEN}✅ ${iface} MTU 已临时设置为 ${mtu}${PLAIN}" "${GREEN}✅ ${iface} MTU has been temporarily set to ${mtu}${PLAIN}" "${GREEN}✅ ${iface} MTU временно установлен на ${mtu}.${PLAIN}")"
}

network_renew_dhcp() {
    local iface
    iface=$(network_choose_iface) || return 1
    confirm_danger "$(localized_text "刷新 ${iface} DHCP 租约" "Refresh ${iface} DHCP lease" "Обновить аренду DHCP ${iface}")" \
        "$(localized_text "网卡 ${iface} 的地址租约/网络连接" "Address lease/network connection for network card ${iface}" "Аренда адреса/сетевое подключение для сетевой карты ${iface}")" \
        "$(localized_text "通过云厂商控制台重连，或重启系统恢复网络" "Reconnect through the cloud provider console or restart the system to restore the network" "Повторно подключитесь через консоль облачного провайдера или перезагрузите систему для восстановления сети.")" \
        "$(localized_text "如果这是当前 SSH 使用的公网网卡，刷新租约可能短暂断开连接。" "If this is the public card currently used by SSH, refreshing the lease may temporarily disconnect it." "Если это интернет-карта, используемая в настоящее время SSH, обновление аренды может привести к кратковременному отключению.")" || return 1
    if command -v dhclient >/dev/null 2>&1; then
        dhclient -r "$iface" >/dev/null 2>&1 || true
        dhclient "$iface" || return 1
    elif command -v networkctl >/dev/null 2>&1; then
        networkctl renew "$iface" || return 1
    elif command -v nmcli >/dev/null 2>&1; then
        nmcli device reapply "$iface" || nmcli device connect "$iface" || return 1
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 dhclient/networkctl/nmcli，无法自动刷新 DHCP。${PLAIN}" "${YELLOW}⚠️ dhclient/networkctl/nmcli not detected, unable to automatically refresh DHCP.${PLAIN}" "${YELLOW}⚠️ dhclient/networkctl/nmcli не обнаружен, невозможно автоматически обновить DHCP.${PLAIN}")"
        return 1
    fi
    echo -e "$(localized_text "${GREEN}✅ 已尝试刷新 ${iface} 的 DHCP/网络连接。${PLAIN}" "${GREEN}✅ Attempted to refresh DHCP/network connection for ${iface}.${PLAIN}" "${GREEN}✅ Попытка обновить DHCP/сетевое соединение для ${iface}.${PLAIN}")"
}

func_network_interface_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "网络/内核优化 > 网卡管理" "Network/Kernel Optimization > Network interfaces" "Оптимизация сети/ядра > Сетевые интерфейсы")"
        echo -e "$(localized_text "${BOLD}🧰 网卡管理${PLAIN}" "${BOLD}🧰 Network interfaces${PLAIN}" "${BOLD}🧰 Сетевые интерфейсы${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}查看网卡、路由、DNS 和链路状态；关闭网卡等高风险操作会再次确认。${PLAIN}" "${YELLOW}Inspect interfaces, routes, DNS, and link status. High-risk actions such as disabling an interface require confirmation.${PLAIN}" "${YELLOW}Просмотр интерфейсов, маршрутов, DNS и состояния соединения. Опасные действия, включая отключение интерфейса, требуют подтверждения.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 查看网卡 / 路由 / DNS 概览${PLAIN}" "${GREEN}  1. View interfaces, routes, and DNS${PLAIN}" "${GREEN}  1. Показать интерфейсы, маршруты и DNS${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 查看网卡详情与流量统计${PLAIN}" "${GREEN}  2. View interface details and traffic${PLAIN}" "${GREEN}  2. Показать сведения и трафик интерфейса${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 启用指定网卡${PLAIN}" "${GREEN}  3. Enable an interface${PLAIN}" "${GREEN}  3. Включить интерфейс${PLAIN}")"
        echo -e "$(localized_text "${RED}  4. 关闭指定网卡${PLAIN}" "${RED}  4. Disable an interface${PLAIN}" "${RED}  4. Отключить интерфейс${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}  5. 临时设置网卡 MTU${PLAIN}" "${YELLOW}  5. Set interface MTU temporarily${PLAIN}" "${YELLOW}  5. Временно изменить MTU интерфейса${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}  6. 刷新 DHCP / 网络连接${PLAIN}" "${YELLOW}  6. Renew DHCP / network connection${PLAIN}" "${YELLOW}  6. Обновить DHCP / сетевое соединение${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice
        read_trimmed choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
        case "$choice" in
            1) network_show_overview; pause_return ;;
            2) network_show_iface_detail; pause_return ;;
            3) network_set_iface_state up; pause_return ;;
            4) network_set_iface_state down; pause_return ;;
            5) network_set_iface_mtu; pause_return ;;
            6) network_renew_dhcp; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 24. 网络加速与内核优化菜单 (二级直达)
# ---------------------------------------------------------
