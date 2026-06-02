# shellcheck shell=bash
# SSH hardening menus and high-level security workflows.

func_ssh_login_mode_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "SSH 安全中心 > 用户密钥登录模式"
        echo -e "${BOLD}🔐 用户密钥登录模式${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "PubkeyAuthentication      : ${CYAN}$(ssh_effective_setting PubkeyAuthentication || echo 未知)${PLAIN}"
        echo -e "PasswordAuthentication    : ${CYAN}$(ssh_effective_setting PasswordAuthentication || echo 未知)${PLAIN}"
        echo -e "KbdInteractiveAuthentication: ${CYAN}$(ssh_effective_setting KbdInteractiveAuthentication || echo 未知)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 添加/更新用户 SSH 公钥（不改登录方式）${PLAIN}"
        echo -e "${GREEN}  2. 密钥 + 密码登录（保留/恢复密码）${PLAIN}"
        echo -e "${RED}  3. 仅密钥登录，禁用密码登录${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice user key_count
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1)
                user=$(ssh_choose_user) || { pause_return; continue; }
                ssh_add_public_key_for_user "$user"
                pause_return
                ;;
            2) ssh_apply_auth_mode key_preferred; pause_return ;;
            3)
                user=$(ssh_choose_user) || { pause_return; continue; }
                key_count=$(ssh_authorized_key_count "$user")
                if [[ "$key_count" -eq 0 ]]; then
                    echo -e "${RED}❌ 用户 ${user} 还没有 authorized_keys，不能切到仅密钥登录。${PLAIN}"
                    echo -e "${YELLOW}请先用本菜单 [1] 添加公钥，并用新 SSH 窗口测试成功。${PLAIN}"
                    pause_return
                    continue
                fi
                echo -e "${YELLOW}检测到 ${user} 已有 ${key_count} 条公钥。切换后密码登录会被禁用。${PLAIN}"
                ssh_apply_auth_mode key_only
                pause_return
                ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_ssh_security_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "SSH 安全中心"
        echo -e "${BOLD}🛡️ SSH 安全中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 修改 SSH 端口${PLAIN}             ${YELLOW}(防失联校验和回滚)${PLAIN}"
        echo -e "${GREEN}  2. 用户密钥登录模式${PLAIN}         ${YELLOW}(添加公钥 / 切换密钥或密码登录)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1) func_security ;;
            2) func_ssh_login_mode_menu ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_security() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ SSH 安全加固 (端口修改与防失联)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍：该脚本将修改 SSH 端口并配置防失联机制，确保服务稳定。${PLAIN}"
    echo -e "------------------------------------------------"
    
    # 1. 极致精准：读取内存和进程，获取当前真实生效的 SSH 端口
    local current_p sshd_bin
    sshd_bin=$(command -v sshd 2>/dev/null || true)
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | head -n1)
    if [[ -z "$current_p" && -n "$sshd_bin" ]]; then
        ssh_prepare_runtime_dir >/dev/null 2>&1 || true
        current_p=$("$sshd_bin" -T 2>/dev/null | grep -i "^port " | awk '{print $2}' | head -n1)
    fi
    current_p=${current_p:-22}

    local final_p
    # 交互提示优化：引导用户使用高位端口避开特权冲突
    read_trimmed final_p "👉 当前生效的 SSH 端口为 $current_p, 请输入新端口 [10000-65535] (回车保持不变): "
    final_p=${final_p:-$current_p}

    if [[ "$final_p" != "$current_p" ]]; then
        if [[ -z "$sshd_bin" ]]; then
            echo -e "${RED}❌ 未找到 sshd 命令，无法安全校验 SSH 配置，已取消。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        if ! command -v systemctl >/dev/null 2>&1; then
            echo -e "${RED}❌ 未检测到 systemctl，无法安全重启 SSH 服务，已取消。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        if ! ssh_prepare_runtime_dir; then
            echo -e "${RED}❌ 无法创建 /run/sshd，sshd 无法完成语法检查。请确认当前为 root 权限。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        # [严格检验] 端口合法性
        if ! [[ "$final_p" =~ ^[0-9]+$ ]] || (( 10#$final_p < 10000 || 10#$final_p > 65535 )); then
            echo -e "${RED}❌ 错误：无效的端口号！必须是 10000-65535 之间的纯数字。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        echo -e "${YELLOW}即将修改：/etc/ssh/sshd_config、/etc/ssh/sshd_config.d、SSH systemd socket/服务、系统防火墙放行规则。${PLAIN}"
        echo -e "${YELLOW}请先确认云厂商安全组已经放行 ${final_p}/tcp，并保留当前 SSH 会话。${PLAIN}"
        confirm_danger "修改 SSH 端口为 ${final_p}" "新端口未放行会导致后续无法重新连接 SSH。" "脚本会先备份 sshd_config，校验语法失败或服务重启失败时自动回滚。" || {
            echo -e "${BLUE}已取消 SSH 端口修改。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        }

        echo -e "${CYAN}▶ 正在备份原生 SSH 配置文件...${PLAIN}"
        local backup_file="/etc/ssh/sshd_config.bak_$(date +%s)"
        if ! cp -p /etc/ssh/sshd_config "$backup_file"; then
            echo -e "${RED}❌ SSH 配置备份失败，已取消修改。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        # 2. 核心黑科技：安全的置顶替换
        # - 先安全删除所有带 Port 的行 (忽略注释符和空格)
        # - 然后在文件绝对第一行 (1i) 插入新端口，秒杀所有 include 配置覆盖！
        if ! sed -i '/^[[:space:]]*#\?Port /d' /etc/ssh/sshd_config || ! sed -i "1i Port $final_p" /etc/ssh/sshd_config; then
            echo -e "${RED}❌ 写入 SSH 配置失败，正在恢复备份。${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        if ! ssh_write_sshd_port_dropin "$final_p"; then
            echo -e "${RED}❌ 写入 SSH drop-in 端口配置失败，正在恢复备份。${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        # 3. [CentOS 专属] SELinux 放行
        if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
            echo -e "${YELLOW}检测到 SELinux 开启，正在配置底层端口安全策略...${PLAIN}"
            if command -v semanage >/dev/null 2>&1; then
                semanage port -a -t ssh_port_t -p tcp "$final_p" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$final_p" 2>/dev/null
            else
                echo -e "${RED}❌ 致命错误：缺少 semanage 工具！已触发安全回滚。${PLAIN}"
                ssh_rollback_port_change "$backup_file" "$current_p" false
                read -n 1 -s -r -p "按任意键返回..."
                return
            fi
        fi

        # 4. 防失联核心：验证新配置语法
        if ! "$sshd_bin" -t; then
            echo -e "${RED}❌ 致命错误：SSH 配置存在语法异常！正在全盘恢复...${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        
        # 5. 放行全栈防火墙
        if command -v ufw >/dev/null 2>&1; then ufw allow "$final_p"/tcp >/dev/null 2>&1; fi
        if command -v firewall-cmd >/dev/null 2>&1; then 
            firewall-cmd --permanent --add-port="$final_p"/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        fi
        if command -v iptables >/dev/null 2>&1; then
            iptables -I INPUT -p tcp --dport "$final_p" -j ACCEPT 2>/dev/null || true
        fi
        
        # 6. systemd Socket 端口接管：兼容 Ubuntu/Debian 云镜像的 ssh.socket 与 sshd.socket
        local socket_managed=false socket_units
        socket_units=$(ssh_socket_units_for_host | tr '\n' ' ')
        if [[ -n "$socket_units" ]]; then
            echo -e "${YELLOW}检测到 SSH socket (${socket_units})，正在同步底层监听端口...${PLAIN}"
            if ssh_write_socket_port_dropins "$final_p"; then
                socket_managed=true
                systemctl daemon-reload >/dev/null 2>&1 || true
            else
                echo -e "${RED}❌ 写入 SSH socket drop-in 失败，正在回滚。${PLAIN}"
                ssh_rollback_port_change "$backup_file" "$current_p" false
                read -n 1 -s -r -p "按任意键返回..."
                return
            fi
        fi
        
        # 7. 严格隔离的服务重启逻辑
        echo -e "${CYAN}▶ 正在重启底层 SSH 引擎...${PLAIN}"
        local restart_ok=false
        if $socket_managed; then
            if ssh_restart_socket_units; then
                restart_ok=true
                ssh_service_restart >/dev/null 2>&1 || true
            fi
        else
            ssh_service_restart && restart_ok=true
        fi
        
        if $restart_ok; then
            echo -e "${GREEN}✅ SSH 端口已成功更改为 $final_p 并自动放行！${PLAIN}"
            echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
        else
            echo -e "${RED}❌ 致命错误：重启 SSH 服务失败！正在回滚至原端口...${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" "$socket_managed"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
        echo -e "${YELLOW}⚠️ 终极保命提示：${PLAIN}"
        echo -e "现在的这扇 SSH 窗口【千万不要关闭】！"
        echo -e "请立刻使用新端口 $final_p 新建一个连接进行测试。"
        echo -e "如果云平台有【安全组】，请确保也已放行 $final_p 端口！"
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
    else
        echo -e "${BLUE}端口未做更改。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 新增：Fail2ban 防爆破系统管理 (抽象精简版)
# ---------------------------------------------------------

func_add_ssh_key() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔑 添加 SSH 公钥登录 (免密安全认证)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}使用 SSH 密钥登录不仅免去输密码的烦恼，更能彻底免疫密码爆破！${PLAIN}"
    echo -e "请准备好您的公钥 (通常以 ssh-rsa, ssh-ed25519、ecdsa 或 sk-* 开头)。"
    echo -e "------------------------------------------------"
    local user enable_mode
    user=$(ssh_choose_user) || { read -n 1 -s -r -p "按任意键继续..."; return; }
    if ssh_add_public_key_for_user "$user"; then
        echo -e "${GREEN}✅ 公钥添加完成。请立刻新开一个 SSH 窗口测试私钥登录。${PLAIN}"
        read_trimmed enable_mode "是否同时写入“密钥 + 密码登录（保留/恢复密码）”模式？(y/N): "
        if [[ "$enable_mode" =~ ^[Yy]$ ]]; then
            ssh_apply_auth_mode key_preferred || true
        fi
        echo -e "${YELLOW}确认私钥登录 100% 成功后，可进入 [6 SSH 安全中心] -> [2 用户密钥登录模式] 禁用密码登录。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 5. Docker 深度管理 (重构版：非破坏性修改与防宕机回滚)
# ---------------------------------------------------------
