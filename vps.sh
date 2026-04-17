#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 终极全能面板 (Omnitt 联动版)
#  Features: Omnitt动态调参/换内核/ZRAM/Docker/流量监控/加固
#  Shortcut: cy
# =========================================================

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PLAIN='\033[0m'
BOLD='\033[1m'

# 权限与系统检查
[[ $EUID -ne 0 ]] && echo -e "${RED}❌ 错误：请以 root 运行！${PLAIN}" && exit 1

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

# ---------------------------------------------------------
# 零、 注册全局快捷键 (cy)
# ---------------------------------------------------------
create_shortcut() {
    local script_path="/usr/local/bin/cy"
    if [ ! -f "$script_path" ] && [ -f "$0" ]; then
        cp "$(readlink -f "$0")" "$script_path"
        chmod +x "$script_path"
        echo -e "${GREEN}✅ 快捷指令 'cy' 已全局注册！下次可直接输入 cy 唤出面板。${PLAIN}"
        sleep 1
    fi
}

# ---------------------------------------------------------
# 1. 基础环境与系统优化
# ---------------------------------------------------------
func_base_init() {
    clear
    echo -e "${CYAN}👉 正在安装常用工具并限制系统日志...${PLAIN}"
    if [[ "$OS" =~ debian|ubuntu ]]; then
        apt update -qq && apt install -y curl wget git nano unzip htop unattended-upgrades -qq > /dev/null 2>&1
        echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
        dpkg-reconfigure -f noninteractive unattended-upgrades > /dev/null 2>&1
    elif [[ "$OS" =~ centos|rhel|rocky|almalinux ]]; then
        yum install -y curl wget git nano unzip htop epel-release dnf-automatic -q > /dev/null 2>&1
        systemctl enable --now dnf-automatic.timer > /dev/null 2>&1
    fi

    # 日志限制 100M
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/99-limit.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF
    systemctl restart systemd-journald > /dev/null 2>&1
    timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1
    
    echo -e "${GREEN}✅ 基础工具安装完毕，自动更新已开启，日志上限已设为 100M！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 2. 动态 TCP 网络调优 (Omnitt 联动)
# ---------------------------------------------------------
func_tcp_tune() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🌐 动态 TCP 网络调优 (由 Omnitt 强力驱动)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}💡 提示：不同服务器的内存和网络环境差异巨大，盲目套用网上的参数极易导致机器宕机。${PLAIN}"
    echo -e "${YELLOW}我们为您准备了智能参数生成器，请在浏览器中打开以下网站：${PLAIN}"
    echo -e ""
    echo -e "${BOLD}${BLUE}👉 https://omnitt.com/ ${PLAIN}"
    echo -e ""
    echo -e "${GREEN}操作步骤：${PLAIN}"
    echo -e " 1. 访问上方网站，输入您的机器真实配置和网络环境。"
    echo -e " 2. 点击生成，并【复制】网站给出的执行命令或多行代码。"
    echo -e " 3. 按下回车键，我们将打开一个临时编辑器，请【右键粘贴】代码后保存。"
    echo -e "   ${YELLOW}(保存方法: 键盘按 Ctrl+O，回车确认，按 Ctrl+X 退出)${PLAIN}"
    echo -e "------------------------------------------------"
    read -p "👉 复制好代码后，按【回车键】打开编辑器 (输入 n 取消): " open_editor

    if [[ -z "$open_editor" ]] || [[ "$open_editor" =~ ^[Yy]$ ]]; then
        temp_file="/tmp/omnitt_tune_$(date +%s).sh"
        echo -e "#!/bin/bash\n# 在此下方粘贴来自 https://omnitt.com/ 的代码:\n" > "$temp_file"
        
        # 打开 Nano 让用户粘贴
        nano "$temp_file"
        
        # 校验文件是否被修改（如果大于初始字节说明粘贴了代码）
        if [ $(wc -c < "$temp_file") -gt 60 ]; then
            echo -e "\n${CYAN}👉 正在执行您粘贴的优化代码...${PLAIN}"
            bash "$temp_file"
            echo -e "${GREEN}✅ 定制 TCP 网络调优已成功应用！${PLAIN}"
        else
            echo -e "\n${YELLOW}⚠️ 未检测到有效代码，已取消执行。${PLAIN}"
        fi
        rm -f "$temp_file"
    else
        echo -e "\n${YELLOW}已取消 TCP 调优。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 3. SSH 安全加固 (端口 + Fail2ban)
# ---------------------------------------------------------
func_security() {
    clear
    echo -e "${CYAN}👉 安全加固模块${PLAIN}"
    current_ssh_port=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    current_ssh_port=${current_ssh_port:-22}
    
    echo -e "当前 SSH 端口为: ${GREEN}${current_ssh_port}${PLAIN}"
    read -p "请输入新 SSH 端口 (直接回车保持不变): " new_port
    final_port=${new_port:-$current_ssh_port}

    if [[ "$final_port" != "$current_ssh_port" ]]; then
        sed -i "s/^#Port .*/Port $final_port/" /etc/ssh/sshd_config
        sed -i "s/^Port .*/Port $final_port/" /etc/ssh/sshd_config
        grep -q "^Port $final_port" /etc/ssh/sshd_config || echo "Port $final_port" >> /etc/ssh/sshd_config
        
        if command -v ufw >/dev/null 2>&1; then ufw allow "$final_port"/tcp >/dev/null;
        elif command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --permanent --add-port="$final_port"/tcp >/dev/null; firewall-cmd --reload >/dev/null; fi
        echo -e "${GREEN}✅ SSH 端口已修改为: $final_port${PLAIN}"
    fi

    if [[ "$OS" =~ debian|ubuntu ]]; then apt install -y fail2ban -qq > /dev/null 2>&1; else yum install -y fail2ban -q > /dev/null 2>&1; fi
    cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port    = $final_port
findtime = 10m
maxretry = 5
bantime = 24h
EOF
    systemctl restart fail2ban > /dev/null 2>&1
    echo -e "${GREEN}✅ Fail2ban 暴力破解防护已生效！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 4. 安装 Docker 环境
# ---------------------------------------------------------
func_docker() {
    clear
    if command -v docker >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 检测到 Docker 已安装，无需重复操作。${PLAIN}"
    else
        echo -e "${CYAN}👉 正在调用官方脚本安装 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker > /dev/null 2>&1
        echo -e "${GREEN}✅ Docker 安装完成！${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 5. 换装 Cloud 内核
# ---------------------------------------------------------
func_install_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then
        echo -e "${RED}❌ 此功能仅支持 Debian/Ubuntu 系统。${PLAIN}"
    else
        echo -e "${CYAN}👉 正在更新源并安装 Cloud 内核...${PLAIN}"
        apt update -y
        apt install -y linux-image-cloud-amd64
        echo -e "${GREEN}✅ Cloud 内核安装完成！请在主菜单选择重启以加载新内核。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 6. 清理旧内核
# ---------------------------------------------------------
func_clean_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then
        echo -e "${RED}❌ 此功能仅支持 Debian/Ubuntu 系统。${PLAIN}"
    else
        echo -e "${YELLOW}当前正在运行的内核: $(uname -r)${PLAIN}"
        echo -e "${CYAN}👉 已安装的内核列表：${PLAIN}"
        echo "------------------------------------------------"
        dpkg --list | grep linux-image
        echo "------------------------------------------------"
        echo -e "${RED}🔴 警告：绝对不要卸载带有 'cloud' 字样的内核，以及当前运行的内核！${PLAIN}"
        echo -e "💡 示例输入: linux-image-amd64 linux-image-6.12.63+deb13-amd64"
        echo ""
        read -p "✍️ 请输入要卸载的旧内核包名 (直接回车取消): " old_kernels
        
        if [ -n "$old_kernels" ]; then
            apt purge -y $old_kernels
            update-grub
            apt autoremove --purge -y
            echo -e "${GREEN}✅ 旧内核已彻底清理！${PLAIN}"
        else
            echo -e "${YELLOW}已取消清理操作。${PLAIN}"
        fi
    fi
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 7. 智能硬件检测与极限内存调优 (ZRAM + Swap)
# ---------------------------------------------------------
func_zram_swap() {
    clear
    echo -e "${CYAN}👉 正在读取系统硬件配置...${PLAIN}"
    
    mem_total=$(free -m | awk '/^Mem:/{print $2}')
    mem_gb=$(awk "BEGIN {printf \"%.1f\", $mem_total/1024}")
    
    if [ "$mem_total" -le 1536 ]; then
        rec_zram=100; rec_swap=100; rec_vfs=50; tier_name="1GB及以下 (激进配置)"
    elif [ "$mem_total" -le 6144 ]; then
        rec_zram=70; rec_swap=60; rec_vfs=50; tier_name="2GB~4GB (积极配置)"
    else
        rec_zram=25; rec_swap=10; rec_vfs=100; tier_name="8GB及以上 (保守配置)"
    fi

    echo "------------------------------------------------"
    echo -e "🖥️  检测到物理内存: ${GREEN}${mem_gb} GB${PLAIN}"
    echo -e "⚙️  自动匹配硬件档位: ${YELLOW}${tier_name}${PLAIN}"
    echo ""
    echo -e "${CYAN}💡 算法推荐最佳参数如下：${PLAIN}"
    echo -e "   - ZRAM 内存压缩占比: ${GREEN}${rec_zram}%${PLAIN}"
    echo -e "   - 系统 Swappiness 倾向: ${GREEN}${rec_swap}${PLAIN}"
    [[ "$rec_vfs" == "50" ]] && echo -e "   - 额外释放 VFS 文件缓存: ${GREEN}已开启${PLAIN}"
    echo "------------------------------------------------"

    read -p "是否应用系统推荐的优化方案？(回车默认应用推荐, 输入 n 手动选择): " use_rec

    if [[ -z "$use_rec" || "$use_rec" =~ ^[Yy]$ ]]; then
        final_zram=$rec_zram; final_swap=$rec_swap; final_vfs=$rec_vfs
        echo -e "${GREEN}✅ 已采用自动推荐参数！${PLAIN}"
    else
        echo "------------------------------------------------"
        echo " 1. [激进] 1GB RAM 及以下 (ZRAM 100%, swappiness=100)"
        echo " 2. [积极] 2GB ~ 4GB RAM  (ZRAM 70%, swappiness=60)"
        echo " 3. [保守] 8GB RAM 及以上 (ZRAM 25%, swappiness=10)"
        echo "------------------------------------------------"
        read -p "✍️ 请手动选择档位 [1/2/3]: " manual_choice
        case $manual_choice in
            1) final_zram=100; final_swap=100; final_vfs=50 ;;
            2) final_zram=70; final_swap=60; final_vfs=50 ;;
            3) final_zram=25; final_swap=10; final_vfs=100 ;;
            *) final_zram=70; final_swap=60; final_vfs=50; echo -e "${YELLOW}未知输入，已默认使用积极档位${PLAIN}" ;;
        esac
    fi

    if [[ "$OS" =~ debian|ubuntu ]]; then
        echo -e "${CYAN}👉 正在配置 ZRAM...${PLAIN}"
        apt update -y -qq && apt install -y zram-tools -qq
        cat > /etc/default/zramswap <<EOF
ALGO=zstd
PERCENT=$final_zram
PRIORITY=100
EOF
        systemctl restart zramswap > /dev/null 2>&1
    fi

    if [ ! -f /swapfile ]; then
        echo -e "${CYAN}👉 正在创建 2GB 硬盘 Swap 保底防线...${PLAIN}"
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
        chmod 600 /swapfile
        mkswap /swapfile > /dev/null 2>&1
        swapon --priority -2 /swapfile
        grep -q "/swapfile" /etc/fstab || echo '/swapfile none swap sw,pri=-2 0 0' >> /etc/fstab
    fi

    echo -e "${CYAN}👉 正在写入系统内存管理倾向...${PLAIN}"
    echo "vm.swappiness=$final_swap" > /etc/sysctl.d/99-memory-tune.conf
    [[ "$final_vfs" == "50" ]] && echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-memory-tune.conf
    sysctl -p /etc/sysctl.d/99-memory-tune.conf > /dev/null 2>&1
    
    echo -e "${GREEN}✅ 智能内存与 I/O 调优已完成！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 8. 端口流量监控
# ---------------------------------------------------------
func_traffic_dog() {
    clear
    echo -e "${CYAN}👉 正在拉取并运行端口流量狗 (port-traffic-dog)...${PLAIN}"
    wget -qO port-traffic-dog.sh https://raw.githubusercontent.com/zywe03/realm-xwPF/main/port-traffic-dog.sh
    if [ -f "port-traffic-dog.sh" ]; then
        chmod +x port-traffic-dog.sh
        ./port-traffic-dog.sh
    else
        echo -e "${RED}❌ 脚本下载失败，请检查网络！${PLAIN}"
    fi
    echo ""
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 界面主循环
# ---------------------------------------------------------
main_menu() {
    create_shortcut
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🚀 VPS 终极全能面板 (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 基础环境初始化 ${YELLOW}(安装工具/自动更新/日志瘦身)${PLAIN}"
        echo -e "${GREEN}  2. 动态TCP网络调优${YELLOW}(🔗 跳转 Omnitt 智能生成配置)${PLAIN}"
        echo -e "${GREEN}  3. SSH 安全加固   ${YELLOW}(修改端口 / Fail2ban 防爆破)${PLAIN}"
        echo -e "${GREEN}  4. 安装 Docker    ${YELLOW}(一键调用官方脚本部署环境)${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${GREEN}  5. 换装 Cloud内核 ${YELLOW}(释放硬件驱动，KVM虚拟化专属)${PLAIN}"
        echo -e "${GREEN}  6. 清理旧版内核   ${YELLOW}(释放 /boot 空间，需谨慎操作)${PLAIN}"
        echo -e "${GREEN}  7. 智能内存调优   ${YELLOW}(硬件自适应配置 ZRAM + Swap)${PLAIN}"
        echo -e "${GREEN}  8. 端口流量监控   ${YELLOW}(拉取运行 port-traffic-dog)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${RED}  9. 重启系统       ${YELLOW}(使内核等参数彻底生效)${PLAIN}"
        echo -e "${RED}  0. 退出面板${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请输入数字选择功能: " choice

        case $choice in
            1) func_base_init ;;
            2) func_tcp_tune ;;
            3) func_security ;;
            4) func_docker ;;
            5) func_install_kernel ;;
            6) func_clean_kernel ;;
            7) func_zram_swap ;;
            8) func_traffic_dog ;;
            9) 
                read -p "⚠️ 确定要重启服务器吗？(y/n): " confirm_reboot
                [[ "$confirm_reboot" =~ ^[Yy]$ ]] && reboot
                ;;
            0) 
                clear
                echo -e "${GREEN}👋 感谢使用！记得随时输入 'cy' 唤出面板。${PLAIN}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}❌ 无效的输入，请重新输入！${PLAIN}"
                sleep 1 
                ;;
        esac
    done
}

# 启动主程序
main_menu
