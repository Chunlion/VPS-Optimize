#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 终极全能面板 (Omnitt 智能防呆版)
#  Features: 动态参数防呆录入/换内核/ZRAM/Docker/流量监控
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
# 核心函数：逐行安全应用 sysctl (防报错神器)
# ---------------------------------------------------------
apply_sysctl_settings() {
    local conf_file="$1"
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        local key value
        key=$(echo "$line" | cut -d= -f1 | tr -d ' ')
        value=$(echo "$line" | cut -d= -f2- | tr -d ' ')
        if [[ -n "$key" && -n "$value" ]]; then
            sysctl -w "${key}=${value}" > /dev/null 2>&1
        fi
    done < "$conf_file"
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
# 2. 动态 TCP 网络调优 (防呆多行录入版)
# ---------------------------------------------------------
func_tcp_tune() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🌐 动态 TCP 网络调优 (由 Omnitt 强力驱动)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}💡 提示：盲目套用参数极易导致机器宕机。${PLAIN}"
    echo -e "${YELLOW}请在浏览器中打开以下网站，生成您的专属配置：${PLAIN}\n"
    echo -e "${BOLD}${BLUE}👉 https://omnitt.com/ ${PLAIN}\n"
    echo -e "${GREEN}操作步骤：${PLAIN}"
    echo -e " 1. 访问网站，输入机器真实配置和网络环境。"
    echo -e " 2. 点击生成，并【复制】网站给出的 ${YELLOW}参数文本${PLAIN} (如 net.core.rmem_max=...)"
    echo -e " 3. 按回车键继续，然后在终端直接【右键粘贴】所有代码。"
    echo -e " 4. 粘贴完成后，在新的一行输入 ${RED}EOF${PLAIN} 并按回车确认！"
    echo -e "------------------------------------------------"
    read -p "👉 准备好粘贴了吗？(回车继续，输入 n 取消): " start_paste
    
    if [[ -n "$start_paste" ]] && [[ ! "$start_paste" =~ ^[Yy]$ ]]; then
        echo -e "\n${YELLOW}已取消 TCP 调优。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        return
    fi

    echo -e "\n${CYAN}👇 请在此处右键粘贴代码，完成后在新行输入 EOF 并按回车：${PLAIN}"
    
    temp_file="/etc/sysctl.d/99-omnitt-tune.conf"
    > "$temp_file" # 清空历史配置文件
    
    # 静默吸收所有用户输入，直到识别到 EOF
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r') # 清理 Windows 换行符
        if [[ "$line" == "EOF" || "$line" == "eof" ]]; then
            break
        fi
        echo "$line" >> "$temp_file"
    done
    
    # 校验是否真的有参数写入
    if [ -s "$temp_file" ]; then
        echo -e "\n${CYAN}👉 正在为您应用定制的网络参数...${PLAIN}"
        # 调用核心函数逐行安全写入
        apply_sysctl_settings "$temp_file"
        
        # 顺手提升文件句柄数以配合 TCP 参数
        if ! grep -q "1000000" /etc/security/limits.conf; then
            cat >> /etc/security/limits.conf <<EOF
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
        fi
        echo -e "${GREEN}✅ 定制 TCP 网络调优已成功应用！${PLAIN}"
    else
        echo -e "\n${YELLOW}⚠️ 未检测到有效参数，已取消操作。${PLAIN}"
        rm -f "$temp_file"
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
# 4. 安装 Docker 环境 与 安全加固
# ---------------------------------------------------------
func_docker() {
    clear
    echo -e "${CYAN}👉 正在检查 Docker 环境...${PLAIN}"
    
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${CYAN}👉 正在调用官方脚本安装 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker > /dev/null 2>&1
        echo -e "${GREEN}✅ Docker 安装完成！${PLAIN}"
    else
        echo -e "${GREEN}✅ 检测到 Docker 已安装。${PLAIN}"
    fi

    # Docker 安全与日志防爆盘加固
    echo -e "\n${YELLOW}💡 Docker 默认会绕过防火墙暴露端口，且日志无上限极易撑爆硬盘。${PLAIN}"
    read -p "是否应用 Docker 安全配置？(绑定本地IP防穿透 + 日志限制) [Y/n]: " secure_docker
    
    if [[ -z "$secure_docker" ]] || [[ "$secure_docker" =~ ^[Yy]$ ]]; then
        mkdir -p /etc/docker
        # 写入安全的 daemon.json，不开启可能会引发兼容性问题的 IPv6，只保留核心安全配置
        cat <<EOF > /etc/docker/daemon.json
{
    "ip": "127.0.0.1",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "50m",
        "max-file": "3"
    }
}
EOF
        echo -e "${CYAN}👉 正在重启 Docker 服务应用安全策略...${PLAIN}"
        systemctl daemon-reload
        systemctl restart docker
        echo -e "${GREEN}✅ Docker 安全配置已生效！${PLAIN}"
        echo -e "${YELLOW}⚠️ 注意：此后使用 -p 映射的端口默认仅本地 (127.0.0.1) 可访。${PLAIN}"
        echo -e "${YELLOW}如需向公网直接暴露端口，请明确指定，如：-p 0.0.0.0:8080:80${PLAIN}"
    else
        echo -e "${BLUE}已跳过 Docker 安全配置。${PLAIN}"
    fi
    
    echo ""
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

    read -p "是否应用推荐方案？(回车默认应用, 输入 n 手动选择): " use_rec

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
            *) final_zram=70; final_swap=60; final_vfs=50; echo -e "${YELLOW}未知输入，已默认积极档位${PLAIN}" ;;
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
        echo -e "${GREEN}  2. 动态TCP网络调优${YELLOW}(🔗 联动 Omnitt 专属配置录入)${PLAIN}"
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
