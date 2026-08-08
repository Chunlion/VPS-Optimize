# shellcheck shell=bash
# Fail2ban installation and SSH brute-force protection workflow.

func_fail2ban() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}Fail2ban 防爆破系统管理${PLAIN}" "${BOLD}Fail2ban Explosion-proof system management${PLAIN}" "${BOLD}Fail2ban Управление взрывозащищенной системой${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    
    local current_p
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    if [[ -z "$current_p" ]]; then
        current_p=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    fi
    current_p=${current_p:-22}
    
    echo -e "$(localized_text "${YELLOW}👉 当前系统检测到的 SSH 端口为: ${GREEN}$current_p${PLAIN}" "${YELLOW}👉 The current SSH port detected by the system is: $current_p${PLAIN}" "${YELLOW}👉 Текущий порт SSH, обнаруженный системой: $current_p${PLAIN}")"
    echo -e "------------------------------------------------"
    
    local f2b_status="$(localized_text "${RED}未安装${PLAIN}" "${RED}Is not installed${PLAIN}" "${RED}не установлен${PLAIN}")"
    if command -v fail2ban-server >/dev/null 2>&1; then
        if systemctl is-active --quiet fail2ban; then
            f2b_status="$(localized_text "${GREEN}已运行${PLAIN}" "${GREEN}Has run${PLAIN}" "${GREEN}запустил${PLAIN}")"
        else
            f2b_status="$(localized_text "${YELLOW}已停止${PLAIN}" "${YELLOW}Has stopped${PLAIN}" "${YELLOW}остановлен${PLAIN}")"
        fi
    fi
    
    echo -e "$(localized_text "当前 Fail2ban 状态: [ $f2b_status ]" "Current Fail2ban status: [ $f2b_status ]" "Текущий статус Fail2ban: [ $f2b_status ]")"
    echo -e "$(localized_text "  ${GREEN}1.${PLAIN} 一键安装并配置 Fail2ban ${YELLOW}(自动绑定当前 SSH 端口)${PLAIN}" "${GREEN}1.${PLAIN} One-click installation and configuration Fail2ban ${YELLOW}(automatically bind the current SSH port)${PLAIN}" "${GREEN}1.${PLAIN} Установка и настройка в один клик Fail2ban ${YELLOW}(автоматическая привязка текущего порта SSH)${PLAIN}")"
    echo -e "$(localized_text "  ${BLUE}2.${PLAIN} 更新防护端口 ${YELLOW}(如果您刚改了 SSH 端口，选此项重载)${PLAIN}" "${BLUE}2.${PLAIN} Update protection port ${YELLOW}(If you have just changed the SSH port, select this to overload)${PLAIN}" "${BLUE}2.${PLAIN} Порт защиты обновлений ${YELLOW}(если вы только что изменили порт SSH, выберите его для перегрузки)${PLAIN}")"
    echo -e "$(localized_text "  ${RED}3.${PLAIN} 彻底卸载 Fail2ban" "${RED}3.${PLAIN} Completely uninstall Fail2ban" "${RED}3.${PLAIN} Полностью удалить Fail2ban")"
    echo -e "$(localized_text "  ${RED}0.${PLAIN} 返回主菜单" "${RED}0.${PLAIN} Return to main menu" "${RED}0.${PLAIN} Возврат в главное меню")"
    echo -e "------------------------------------------------"
    
    local f_choice
    read_trimmed f_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"
    
    case $f_choice in
        1|2)
            if [[ "$f_choice" == "1" ]]; then
                echo -e "$(localized_text "${CYAN}正在安装 Fail2ban...${PLAIN}" "${CYAN}Is installing Fail2ban...${PLAIN}" "${CYAN}устанавливает Fail2ban...${PLAIN}")"
                if is_debian; then
                    install_pkg fail2ban python3-systemd
                else
                    install_pkg fail2ban
                fi
            fi
            
            if command -v fail2ban-server >/dev/null 2>&1; then
                echo -e "$(localized_text "${CYAN}正在写入配置并绑定端口 $current_p ...${PLAIN}" "${CYAN}Is writing configuration and binding port $current_p ...${PLAIN}" "${CYAN}записывает конфигурацию и порт привязки $current_p ...${PLAIN}")"
                local f2b_backend="auto"
                if command -v journalctl >/dev/null 2>&1; then
                    f2b_backend="systemd"
                fi
                cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = $current_p
backend = $f2b_backend
EOF
                systemctl enable fail2ban >/dev/null 2>&1
                systemctl restart fail2ban >/dev/null 2>&1
                if systemctl is-active --quiet fail2ban; then
                    echo -e "$(localized_text "${GREEN}✅ Fail2ban 配置完成并已启动！(保护端口: $current_p，日志后端: $f2b_backend)${PLAIN}" "${GREEN}✅ Fail2ban is configured and started! (Protected port: $current_p, log backend: $f2b_backend)${PLAIN}" "${GREEN}✅ Fail2ban настроен и запущен! (Защищенный порт: $current_p, бэкенд журнала: $f2b_backend)${PLAIN}")"
                    echo -e "$(localized_text "${YELLOW}💡 规则：10分钟内密码错误5次，自动封禁该IP 24小时。${PLAIN}" "${YELLOW}💡 Rules: If the password is incorrect 5 times within 10 minutes, the IP will be automatically blocked for 24 hours.${PLAIN}" "${YELLOW}💡 Правила: При неверном пароле 5 раз в течение 10 минут IP автоматически блокируется на 24 часа.${PLAIN}")"
                else
                    echo -e "$(localized_text "${RED}❌ Fail2ban 启动失败，正在显示关键日志：${PLAIN}" "${RED}❌ Fail2ban failed to start, the key log is being displayed:${PLAIN}" "${RED}❌ Fail2ban не удалось запустить, отображается журнал ключей:${PLAIN}")"
                    fail2ban-client -t 2>/dev/null || true
                    journalctl -u fail2ban -n 20 --no-pager 2>/dev/null || true
                fi
            else
                echo -e "$(localized_text "${RED}❌ Fail2ban 安装或检测失败，请检查网络源。${PLAIN}" "${RED}❌ Fail2ban Installation or detection failed, please check the network source.${PLAIN}" "${RED}❌ Fail2ban Не удалось установить или обнаружить, проверьте сетевой источник.${PLAIN}")"
            fi
            ;;
        3)
            echo -e "$(localized_text "${CYAN}正在卸载 Fail2ban...${PLAIN}" "${CYAN}Is uninstalling Fail2ban...${PLAIN}" "${CYAN}удаляет Fail2ban...${PLAIN}")"
            remove_pkg fail2ban # <--- 核心修改：一句话极简卸载
            quarantine_path /etc/fail2ban "/etc/vps-optimize/quarantine" >/dev/null 2>&1 || true
            echo -e "$(localized_text "${GREEN}✅ Fail2ban 已卸载，旧配置已隔离到 /etc/vps-optimize/quarantine。${PLAIN}" "${GREEN}✅ Fail2ban has been uninstalled and the old configuration has been isolated to /etc/vps-optimize/quarantine.${PLAIN}" "${GREEN}✅ Fail2ban удален, а старая конфигурация изолирована от /etc/vps-optimize/quarantine.${PLAIN}")"
            ;;
        0) return ;;
        *) echo -e "$(localized_text "${RED}❌ 无效的输入！${PLAIN}" "${RED}❌ Invalid input!${PLAIN}" "${RED}❌ Неверный ввод!${PLAIN}")"; sleep 1 ;;
    esac
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}
# ---------------------------------------------------------
# 新增功能：添加 SSH 公钥登录
# ---------------------------------------------------------
