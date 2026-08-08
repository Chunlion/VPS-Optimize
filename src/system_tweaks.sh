# shellcheck shell=bash
# System feature toggles and cleanup workflows.

func_system_tweaks() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}⚙️ 系统开关与清理${PLAIN}" "${BOLD}⚙️ System switch and cleaning${PLAIN}" "${BOLD}⚙️ Системный переключатель и очистка${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        
        # 状态获取
        local ipv6_status
        local str_ipv6
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
        if [[ "$ipv6_status" == "0" ]]; then str_ipv6="$(localized_text "${GREEN}开启中${PLAIN}" "${GREEN}Is opening${PLAIN}" "${GREEN}открывает${PLAIN}")"; else str_ipv6="$(localized_text "${RED}已禁用${PLAIN}" "${RED}Disabled${PLAIN}" "${RED}отключен${PLAIN}")"; fi
        
        local str_ipv4_first
        if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then 
            str_ipv4_first="$(localized_text "${GREEN}已优先${PLAIN}" "${GREEN}Has given priority to${PLAIN}" "${GREEN}отдал приоритет${PLAIN}")"
        else 
            str_ipv4_first="$(localized_text "${RED}默认(IPv6优先)${PLAIN}" "${RED}Default (IPv6 takes priority)${PLAIN}" "${RED}по умолчанию (IPv6 имеет приоритет)${PLAIN}")"
        fi
        
        local ping_status
        local str_ping
        ping_status=$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null)
        if [[ "$ping_status" == "0" ]]; then str_ping="$(localized_text "${GREEN}允许被Ping${PLAIN}" "${GREEN}Is allowed to be Ping${PLAIN}" "${GREEN}может быть Ping${PLAIN}")"; else str_ping="$(localized_text "${RED}禁Ping中${PLAIN}" "${RED}Ping banned${PLAIN}" "${RED}Пинг запрещен${PLAIN}")"; fi
        
        local update_status
        local str_update
        if [[ "$OS" =~ debian|ubuntu ]]; then
            update_status=$(systemctl is-active unattended-upgrades 2>/dev/null)
        else
            update_status=$(systemctl is-active dnf-automatic.timer 2>/dev/null)
        fi
        if [[ "$update_status" == "active" ]]; then str_update="$(localized_text "${GREEN}开启中${PLAIN}" "${GREEN}Is opening${PLAIN}" "${GREEN}открывает${PLAIN}")"; else str_update="$(localized_text "${RED}已关闭${PLAIN}" "${RED}Has closed${PLAIN}" "${RED}закрылся${PLAIN}")"; fi

        local current_hostname
        current_hostname=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)
        current_hostname="$(trim_input "$current_hostname")"
        current_hostname="$(localized_text "${current_hostname:-未知}" "${current_hostname:-未知}" "${current_hostname:-未知}")"

        # 完美修复：一字不落的菜单显示
        echo -e "$(localized_text "${GREEN}  1. IPv6 开关${PLAIN}              当前: [ $str_ipv6 ]" "${GREEN}1. IPv6 switch${PLAIN} Current: [ $str_ipv6 ]" "${GREEN}1. Переключатель IPv6${PLAIN} Ток: [ $str_ipv6 ]")"
        echo -e "$(localized_text "${GREEN}  2. IPv4 出站优先${PLAIN}          当前: [ $str_ipv4_first ]" "${GREEN}2. IPv4 Outbound priority${PLAIN} Current: [ $str_ipv4_first ]" "${GREEN}2. IPv4 Приоритет исходящего вызова${PLAIN} Текущий: [ $str_ipv4_first ]")"
        echo -e "$(localized_text "${GREEN}  3. Ping 响应开关${PLAIN}          当前: [ $str_ping ]" "${GREEN}3. Ping response switch${PLAIN} Current: [ $str_ping ]" "${GREEN}3. Переключатель ответа на запрос Ping${PLAIN} Ток: [ $str_ping ]")"
        echo -e "$(localized_text "${GREEN}  4. 本机 hosts 解析管理${PLAIN}    (/etc/hosts 本机域名解析)" "${GREEN}4. Local hosts resolution management${PLAIN} (/etc/hosts local domain resolution)" "${GREEN}4. Управление разрешением локальных хостов${PLAIN} (разрешение локального доменного имени /etc/hosts)")"
        echo -e "$(localized_text "${GREEN}  5. 修改主机名${PLAIN}             当前: [ ${CYAN}${current_hostname}${PLAIN} ]" "${GREEN}5. Modify the host name${PLAIN} Current: [ ${CYAN}${current_hostname}${PLAIN} ]" "${GREEN}5. Измените имя хоста${PLAIN} Текущее: [ ${CYAN}${current_hostname}${PLAIN} ]")"
        echo -e "$(localized_text "${GREEN}  6. 自动安全更新开关${PLAIN}       当前: [ $str_update ]" "${GREEN}6. Automatic security update switch${PLAIN} Current: [ $str_update ]" "${GREEN}6. Переключатель автоматического обновления безопасности${PLAIN} Текущая версия: [ $str_update ]")"
        echo -e "$(localized_text "${GREEN}  7. 清理系统垃圾${PLAIN}           (日志/缓存/无用包)" "${GREEN}7. Clean up system garbage${PLAIN} (log/cache/useless packages)" "${GREEN}7. Очистка системного мусора${PLAIN} (журнал/кеш/бесполезные пакеты)")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回主菜单${PLAIN}" "${RED}0. Return to the main menu${PLAIN}" "${RED}0. Возврат в главное меню.${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local tweak_choice
        read_trimmed tweak_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"
        
        case $tweak_choice in
            1)
                read_trimmed yn "$(localized_text "❓ 开启 IPv6？(y 开启 / n 关闭): " "❓ Turn on IPv6? (y on / n off):" "❓ Включить IPv6? (да вкл./нет выкл.):")"
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    quarantine_path /etc/sysctl.d/99-disable-ipv6.conf "/etc/vps-optimize/quarantine/sysctl" >/dev/null 2>&1 || true
                    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
                    echo -e "$(localized_text "${GREEN}✅ IPv6 已开启${PLAIN}" "${GREEN}✅ IPv6 has opened${PLAIN}" "${GREEN}✅ IPv6 открылся${PLAIN}")"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    [[ -f /etc/sysctl.d/99-disable-ipv6.conf ]] && cp -p /etc/sysctl.d/99-disable-ipv6.conf "/etc/sysctl.d/99-disable-ipv6.conf.bak_$(date +%s)" 2>/dev/null || true
                    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1
                    echo -e "$(localized_text "${RED}✅ IPv6 已禁用${PLAIN}" "${RED}✅ IPv6 has disabled${PLAIN}" "${RED}✅ IPv6 отключил${PLAIN}")"
                fi; sleep 1 ;;
            2)
                read_trimmed yn "$(localized_text "❓ 设置 IPv4 为最高出站优先级？(y 开启 / n 恢复默认): " "❓ Set IPv4 as the highest outbound priority? (y turns on / n returns to default):" "❓ Установить IPv4 как наивысший исходящий приоритет? (y включается/n возвращается к настройкам по умолчанию):")"
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    [[ -f /etc/gai.conf ]] || touch /etc/gai.conf
                    cp -p /etc/gai.conf "/etc/gai.conf.bak_$(date +%s)" 2>/dev/null || true
                    sed -Ei '/^[[:space:]]*#?[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+100\b.*?$/ {s/.+100\b([[:space:]]*#.*)?$/precedence ::ffff:0:0\/96  100\1/; :a;n;b a}; /^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+.*$/ {s/^.*precedence.+::ffff:0:0\/96[^0-9]+([0-9]+).*$/precedence ::ffff:0:0\/96  100\t#原值为 \1/; :a;n;ba;}; $aprecedence ::ffff:0:0\/96  100' /etc/gai.conf
                    echo -e "$(localized_text "${GREEN}✅ 已设为 IPv4 优先${PLAIN}" "${GREEN}✅ has been set to IPv4, giving priority to${PLAIN}" "${GREEN}Для вещества установлено значение IPv4, что дает приоритет.${PLAIN}")"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    [[ -f /etc/gai.conf ]] || touch /etc/gai.conf
                    cp -p /etc/gai.conf "/etc/gai.conf.bak_$(date +%s)" 2>/dev/null || true
                    sed -i '/precedence ::ffff:0:0\/96  100/d' /etc/gai.conf
                    echo -e "$(localized_text "${BLUE}已恢复系统默认${PLAIN}" "${BLUE}Has restored the system default${PLAIN}" "${BLUE}восстановил системные настройки по умолчанию${PLAIN}")"
                fi; sleep 1 ;;
            3)
                read_trimmed yn "$(localized_text "❓ 允许被 Ping？(y 允许 / n 禁止): " "❓ Allow to be pinged? (y allowed / n forbidden):" "❓ Разрешить пинговать? (y разрешено/n запрещено):")"
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    quarantine_path /etc/sysctl.d/99-disable-ping.conf "/etc/vps-optimize/quarantine/sysctl" >/dev/null 2>&1 || true
                    sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1
                    echo -e "$(localized_text "${GREEN}✅ 已允许被 Ping${PLAIN}" "${GREEN}✅ has been allowed to be Ping${PLAIN}" "${GREEN}веществу разрешено быть Ping${PLAIN}")"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    [[ -f /etc/sysctl.d/99-disable-ping.conf ]] && cp -p /etc/sysctl.d/99-disable-ping.conf "/etc/sysctl.d/99-disable-ping.conf.bak_$(date +%s)" 2>/dev/null || true
                    echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf
                    sysctl -p /etc/sysctl.d/99-disable-ping.conf >/dev/null 2>&1
                    echo -e "$(localized_text "${RED}✅ 已开启禁 Ping 保护${PLAIN}" "${RED}✅ Ping ban protection has been enabled${PLAIN}" "${RED}✅ Защита от блокировки Ping включена${PLAIN}")"
                fi; sleep 1 ;;
            4) func_hosts_manage ;;
            5) func_change_hostname; sleep 1 ;;
            6)
                read_trimmed yn "$(localized_text "❓ 开启系统自动更新？(y 开启 / n 关闭): " "❓ Turn on automatic system updates? (y on / n off):" "❓ Включить автоматическое обновление системы? (да вкл./нет выкл.):")"
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        install_pkg unattended-upgrades || { echo -e "$(localized_text "${RED}❌ unattended-upgrades 安装失败。${PLAIN}" "${RED}❌ unattended-upgrades Installation failed.${PLAIN}" "${RED}❌ автоматические обновления Установка не удалась.${PLAIN}")"; sleep 1; continue; }
                        systemctl enable --now unattended-upgrades >/dev/null 2>&1 || echo -e "$(localized_text "${YELLOW}⚠️ unattended-upgrades 服务启用失败，请手动检查。${PLAIN}" "${YELLOW}⚠️ unattended-upgrades Service activation failed, please check manually.${PLAIN}" "${YELLOW}⚠️ unattended-upgrades Не удалось активировать службу, проверьте вручную.${PLAIN}")"
                    else
                        install_pkg dnf-automatic || { echo -e "$(localized_text "${RED}❌ dnf-automatic 安装失败。${PLAIN}" "${RED}❌ dnf-automatic installation failed.${PLAIN}" "${RED}❌ dnf-автоматическая установка не удалась.${PLAIN}")"; sleep 1; continue; }
                        systemctl enable --now dnf-automatic.timer >/dev/null 2>&1 || echo -e "$(localized_text "${YELLOW}⚠️ dnf-automatic.timer 启用失败，请手动检查。${PLAIN}" "${YELLOW}⚠️ dnf-automatic.timer failed to be enabled, please check manually.${PLAIN}" "${YELLOW}⚠️ Не удалось включить dnf-automatic.timer, проверьте вручную.${PLAIN}")"
                    fi
                    echo -e "$(localized_text "${GREEN}✅ 自动更新已开启${PLAIN}" "${GREEN}✅ Automatic update is turned on${PLAIN}" "${GREEN}✅ Автоматическое обновление включено${PLAIN}")"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    if [[ "$OS" =~ debian|ubuntu ]]; then systemctl disable --now unattended-upgrades >/dev/null 2>&1
                    else systemctl disable --now dnf-automatic.timer >/dev/null 2>&1; fi
                    echo -e "$(localized_text "${GREEN}✅ 自动更新已关闭${PLAIN}" "${GREEN}✅ Automatic updates are turned off${PLAIN}" "${GREEN}✅ Автоматические обновления отключены${PLAIN}")"
                fi; sleep 1 ;;
            7)
                echo -e "$(localized_text "${CYAN}👉 正在深度清理系统垃圾...${PLAIN}" "${CYAN}👉 Deep cleaning of system junk...${PLAIN}" "${CYAN}👉 Глубокая очистка системного мусора...${PLAIN}")"
                if [[ "$OS" =~ debian|ubuntu ]]; then 
                    apt autoremove --purge -y >/dev/null 2>&1
                    apt clean >/dev/null 2>&1
                else 
                    yum autoremove -y >/dev/null 2>&1
                    yum clean all >/dev/null 2>&1
                fi
                journalctl --vacuum-time=1d > /dev/null 2>&1
                echo -e "$(localized_text "${GREEN}✅ 清理完成！${PLAIN}" "${GREEN}✅ Cleanup completed!${PLAIN}" "${GREEN}✅ Очистка завершена!${PLAIN}")"
                sleep 1 ;;
            0) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 统一包管理与执行守卫 (新增：请放在 func_env_install 函数上方)
# ---------------------------------------------------------
