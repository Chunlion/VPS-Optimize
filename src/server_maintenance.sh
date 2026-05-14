# shellcheck shell=bash
# Port process release and server reboot workflows.

func_port_kill() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🔍 网络端口占用排查与进程释放${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}当前系统中正在监听的活动端口列表：${PLAIN}"
        echo -e "------------------------------------------------"
        printf "%-10s %-15s %-20s\n" "协议" "端口" "关联进程 (PID)"
        
        ss -tulnp | grep -E 'LISTEN|UNCONN' | while read -r line; do
            local proto=$(echo "$line" | awk '{print $1}')
            local port=$(echo "$line" | awk '{print $5}' | awk -F: '{print $NF}')
            local pid=$(echo "$line" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')
            local proc=$(echo "$line" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
            
            local proc_info=""
            if [[ -z "$proc" || -z "$pid" ]]; then
                proc_info="系统底层 / 无权限读取"
            else
                proc_info="$proc (PID: $pid)"
            fi
            printf "%-10s %-15s %-20s\n" "$proto" "$port" "$proc_info"
        done | sort -n -k2 | uniq
        
        echo -e "------------------------------------------------"
        echo -e "${GREEN}👉 指南：找到您想释放的冲突端口，输入它即可强杀对应进程。${PLAIN}"
        echo -e "${RED}⚠️ 高危：请勿随意终止 sshd (通常为 22) 的端口，否则会断网失联！${PLAIN}"
        echo -e "------------------------------------------------"
        
        local p_choice
        read_trimmed p_choice "❓ 请输入要强杀释放的端口号 (输入 0 返回主菜单): "
        
        if [[ "$p_choice" == "0" ]]; then break; fi
        
        if is_valid_port "$p_choice"; then
            local ssh_match
            ssh_match=$(ss -tulnp 2>/dev/null | awk -v port="$p_choice" '$5 ~ ":" port "$" && $0 ~ /(sshd|ssh)/ {print}')
            if [[ -n "$ssh_match" || "$p_choice" == "22" ]]; then
                echo -e "${RED}❌ 检测到你选择的是 SSH 相关端口或默认 SSH 端口，为避免失联，已拒绝强杀。${PLAIN}"
                sleep 2
                continue
            fi
            confirm_danger "强杀占用端口 ${p_choice} 的进程" "会对 TCP/UDP ${p_choice} 占用进程发送 SIGKILL，相关服务会立即中断。" "如果杀错服务，需要手动重启对应 systemd 服务或容器。" || {
                echo -e "${BLUE}已取消强杀操作。${PLAIN}"
                sleep 1
                continue
            }
            echo -e "${CYAN}▶ 正在调用底层系统命令强杀端口 $p_choice ...${PLAIN}"
            
            # [依赖前置检查]: 确保存在 fuser 工具
            if ! command -v fuser >/dev/null 2>&1; then
                install_pkg psmisc
            fi
            
            # [极简实现]: 一行代码杀掉占用该 TCP/UDP 端口的所有进程
            if fuser -k -9 -n tcp "$p_choice" >/dev/null 2>&1 || fuser -k -9 -n udp "$p_choice" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ 目标进程已被系统底层强制回收 (SIGKILL)。端口已释放！${PLAIN}"
            else
                echo -e "${BLUE}ℹ️ 未发现任何可被终止的进程占用该端口，或权限不足。${PLAIN}"
            fi
            sleep 2
        else
            echo -e "${RED}❌ 输入无效！请输入纯数字端口号。${PLAIN}"
            sleep 1
        fi
    done
}

func_reboot_server() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔁 重启服务器${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    confirm_danger "立即重启服务器" "当前 SSH 会话会断开，所有运行中的服务会短暂中断。" "请确认云厂商控制台可用，并确保关键配置已经保存。" || {
        echo -e "${BLUE}已取消重启操作。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    }
    reboot
}
# ---------------------------------------------------------
# 19. 脚本热更新
# ---------------------------------------------------------
