# shellcheck shell=bash
# Port process release and server reboot workflows.

func_port_kill() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}🔍 端口占用排查与进程终止${PLAIN}" "${BOLD}🔍 Port usage and process termination${PLAIN}" "${BOLD}🔍 Занятые порты и завершение процессов${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}当前系统中正在监听的活动端口列表：${PLAIN}" "${YELLOW}List of active ports currently being listened to in the system:${PLAIN}" "${YELLOW}Список активных портов, которые в данный момент прослушиваются в системе:${PLAIN}")"
        echo -e "------------------------------------------------"
        printf "%-10s %-15s %-20s\n" "$(localized_text "协议" "Protocol" "Протокол")" "$(localized_text "端口" "Port" "Порт")" "$(localized_text "关联进程 (PID)" "Process (PID)" "Процесс (PID)")"
        
        ss -tulnp | grep -E 'LISTEN|UNCONN' | while read -r line; do
            local proto=$(echo "$line" | awk '{print $1}')
            local port=$(echo "$line" | awk '{print $5}' | awk -F: '{print $NF}')
            local pid=$(echo "$line" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')
            local proc=$(echo "$line" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
            
            local proc_info=""
            if [[ -z "$proc" || -z "$pid" ]]; then
                proc_info="$(localized_text "系统底层 / 无权限读取" "System bottom layer / no permission to read" "Нижний уровень системы / нет разрешения на чтение")"
            else
                proc_info="$proc (PID: $pid)"
            fi
            printf "%-10s %-15s %-20s\n" "$proto" "$port" "$proc_info"
        done | sort -n -k2 | uniq
        
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}输入冲突端口后，脚本会强制终止占用该端口的进程。${PLAIN}" "${GREEN}Enter a conflicting port to forcefully terminate its listening process.${PLAIN}" "${GREEN}Введите конфликтующий порт, чтобы принудительно завершить слушающий его процесс.${PLAIN}")"
        echo -e "$(localized_text "${RED}⚠️ 不要终止 SSH 端口；脚本会拒绝处理检测到的 SSH 监听。${PLAIN}" "${RED}⚠️ Do not terminate the SSH port. Detected SSH listeners are rejected.${PLAIN}" "${RED}⚠️ Не завершайте процесс на порту SSH. Обнаруженные слушатели SSH будут отклонены.${PLAIN}")"
        echo -e "------------------------------------------------"
        
        local p_choice
        read_trimmed p_choice "$(localized_text "输入要释放的端口（0 返回）: " "Port to release (0 to return): " "Порт для освобождения (0 — назад): ")"
        
        if [[ "$p_choice" == "0" ]]; then break; fi
        
        if is_valid_port "$p_choice"; then
            local ssh_match
            ssh_match=$(ss -tulnp 2>/dev/null | awk -v port="$p_choice" '$5 ~ ":" port "$" && $0 ~ /(sshd|ssh)/ {print}')
            if [[ -n "$ssh_match" || "$p_choice" == "22" ]]; then
                echo -e "$(localized_text "${RED}❌ 该端口用于 SSH。为避免连接中断，已拒绝终止进程。${PLAIN}" "${RED}❌ This port is used by SSH. Process termination was blocked to prevent disconnection.${PLAIN}" "${RED}❌ Этот порт используется SSH. Завершение процесса заблокировано, чтобы не потерять соединение.${PLAIN}")"
                sleep 2
                continue
            fi
            confirm_danger "$(localized_text "强制终止占用端口 ${p_choice} 的进程" "Forcefully terminate the process using port ${p_choice}" "Принудительно завершить процесс, использующий порт ${p_choice}")" "$(localized_text "将向占用 TCP/UDP ${p_choice} 的进程发送 SIGKILL，相关服务会立即中断。" "SIGKILL will be sent to processes using TCP/UDP port ${p_choice}; related services will stop immediately." "Процессам, использующим TCP/UDP-порт ${p_choice}, будет отправлен SIGKILL; связанные службы немедленно остановятся.")" "$(localized_text "若终止了错误的进程，需要手动重启对应的 systemd 服务或容器。" "If the wrong process is terminated, restart the corresponding systemd service or container manually." "Если завершён не тот процесс, вручную перезапустите соответствующую службу systemd или контейнер.")" || {
                echo -e "$(localized_text "${BLUE}已取消终止操作。${PLAIN}" "${BLUE}Process termination canceled.${PLAIN}" "${BLUE}Завершение процесса отменено.${PLAIN}")"
                sleep 1
                continue
            }
            echo -e "$(localized_text "${CYAN}▶ 正在终止占用端口 $p_choice 的进程...${PLAIN}" "${CYAN}▶ Terminating processes using port $p_choice...${PLAIN}" "${CYAN}▶ Завершение процессов, использующих порт $p_choice...${PLAIN}")"
            
            # [依赖前置检查]: 确保存在 fuser 工具
            if ! command -v fuser >/dev/null 2>&1; then
                install_pkg psmisc
            fi
            
            # [极简实现]: 一行代码杀掉占用该 TCP/UDP 端口的所有进程
            if fuser -k -9 -n tcp "$p_choice" >/dev/null 2>&1 || fuser -k -9 -n udp "$p_choice" >/dev/null 2>&1; then
                echo -e "$(localized_text "${GREEN}✅ 目标进程已被系统底层强制回收 (SIGKILL)。端口已释放！${PLAIN}" "${GREEN}✅ The target process has been forcibly recycled (SIGKILL) by the bottom layer of the system. The port has been released!${PLAIN}" "${GREEN}✅ Целевой процесс был принудительно перезапущен (SIGKILL) нижним уровнем системы. Порт выпущен!${PLAIN}")"
            else
                echo -e "$(localized_text "${BLUE}ℹ️ 未发现任何可被终止的进程占用该端口，或权限不足。${PLAIN}" "${BLUE}ℹ️ No process that can be terminated is found occupying this port, or the permissions are insufficient.${PLAIN}" "${BLUE}ℹ️ Не обнаружено процессов, которые можно завершить, занимающих этот порт, или разрешения недостаточны.${PLAIN}")"
            fi
            sleep 2
        else
            echo -e "$(localized_text "${RED}❌ 输入无效！请输入纯数字端口号。${PLAIN}" "${RED}❌ Invalid input! Please enter a purely numeric port number.${PLAIN}" "${RED}❌ Неверный ввод! Пожалуйста, введите чисто цифровой номер порта.${PLAIN}")"
            sleep 1
        fi
    done
}

func_reboot_server() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔁 重启服务器${PLAIN}" "${BOLD}🔁 Restart the server${PLAIN}" "${BOLD}🔁 Перезагрузите сервер${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    confirm_danger "$(localized_text "立即重启服务器" "Restart the server now" "Перезагрузите сервер сейчас")" "$(localized_text "当前 SSH 会话会断开，所有运行中的服务会短暂中断。" "The current SSH session will be disconnected and all running services will be briefly interrupted." "Текущий сеанс SSH будет отключен, и все работающие службы будут ненадолго прерваны.")" "$(localized_text "请确认云厂商控制台可用，并确保关键配置已经保存。" "Please confirm that the cloud provider console is available and ensure that key configurations have been saved." "Убедитесь, что консоль облачного провайдера доступна, и убедитесь, что ключевые конфигурации сохранены.")" || {
        echo -e "$(localized_text "${BLUE}已取消重启操作。${PLAIN}" "${BLUE}The restart operation has been canceled.${PLAIN}" "${BLUE}Операция перезапуска отменена.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    }
    reboot
}
# ---------------------------------------------------------
# 19. 脚本热更新
# ---------------------------------------------------------
