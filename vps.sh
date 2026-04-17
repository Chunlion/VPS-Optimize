#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 终极全能控制面板 (大一统子菜单版)
#  Features: 状态开关/BBR/Docker/常用环境/探针/面板
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

apply_sysctl() {
    local conf_file="$1"
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        local key=$(echo "$line" | cut -d= -f1 | tr -d ' ')
        local value=$(echo "$line" | cut -d= -f2- | tr -d ' ')
        [[ -n "$key" && -n "$value" ]] && sysctl -w "${key}=${value}" > /dev/null 2>&1
    done < "$conf_file"
}

# ---------------------------------------------------------
# 1. 基础环境与工具初始化 (修复基础 BBR 丢失问题)
# ---------------------------------------------------------
func_base_init() {
    clear
    echo -e "${CYAN}👉 正在安装常用工具、限制系统日志并开启基础 BBR...${PLAIN}"
    if [[ "$OS" =~ debian|ubuntu ]]; then
        apt update -qq && apt install -y curl wget git nano unzip htop -qq > /dev/null 2>&1
    elif [[ "$OS" =~ centos|rhel|rocky|almalinux ]]; then
        yum install -y curl wget git nano unzip htop epel-release -q > /dev/null 2>&1
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
    
    # 强制开启基础 BBR（防遗漏）
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-bbr-init.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-bbr-init.conf
    sysctl -p /etc/sysctl.d/99-bbr-init.conf > /dev/null 2>&1
    
    echo -e "${GREEN}✅ 基础工具安装完毕，时区已同步，系统默认 BBR 已激活！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 2. 系统高级开关 (新增自动更新开关)
# ---------------------------------------------------------
func_system_tweaks() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}⚙️  系统高级开关与清理优化${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        # 获取当前状态
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
        if [[ "$ipv6_status" == "0" ]]; then str_ipv6="${GREEN}开启中${PLAIN}"; else str_ipv6="${RED}已禁用${PLAIN}"; fi
        
        ping_status=$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null)
        if [[ "$ping_status" == "0" ]]; then str_ping="${GREEN}允许被Ping${PLAIN}"; else str_ping="${RED}禁Ping中${PLAIN}"; fi

        if [[ "$OS" =~ debian|ubuntu ]]; then
            update_status=$(systemctl is-active unattended-upgrades 2>/dev/null)
        else
            update_status=$(systemctl is-active dnf-automatic.timer 2>/dev/null)
        fi
        if [[ "$update_status" == "active" ]]; then str_update="${GREEN}开启中${PLAIN}"; else str_update="${RED}已禁用${PLAIN}"; fi

        echo -e "${GREEN}  1. 开启/禁用 IPv6 网络${PLAIN}   当前状态: [ $str_ipv6 ]"
        echo -e "${GREEN}  2. 允许/禁止 被人Ping${PLAIN}    当前状态: [ $str_ping ]"
        echo -e "${GREEN}  3. 开启/禁用 自动更新${PLAIN}    当前状态: [ $str_update ]"
        echo -e "${GREEN}  4. 彻底清理系统垃圾${PLAIN}      (清空无用包、日志、缓存)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择操作: " tweak_choice

        case $tweak_choice in
            1)
                if [[ "$ipv6_status" == "0" ]]; then
                    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf
                    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf > /dev/null 2>&1
                    echo -e "${GREEN}✅ IPv6 已禁用！${PLAIN}"
                else
                    rm -f /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null 2>&1
                    sysctl -w net.ipv6.conf.default.disable_ipv6=0 > /dev/null 2>&1
                    echo -e "${GREEN}✅ IPv6 已恢复开启！${PLAIN}"
                fi
                sleep 1 ;;
            2)
                if [[ "$ping_status" == "0" ]]; then
                    echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf
                    sysctl -p /etc/sysctl.d/99-disable-ping.conf > /dev/null 2>&1
                    echo -e "${GREEN}✅ 已开启禁 Ping 保护！${PLAIN}"
                else
                    rm -f /etc/sysctl.d/99-disable-ping.conf
                    sysctl -w net.ipv4.icmp_echo_ignore_all=0 > /dev/null 2>&1
                    echo -e "${GREEN}✅ 已允许服务器被 Ping！${PLAIN}"
                fi
                sleep 1 ;;
            3)
                echo -e "${CYAN}👉 正在配置自动更新服务...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    if [[ "$update_status" == "active" ]]; then
                        systemctl disable --now unattended-upgrades >/dev/null 2>&1
                        echo -e "${GREEN}✅ 系统自动安全更新已禁用！${PLAIN}"
                    else
                        apt install -y unattended-upgrades -qq >/dev/null 2>&1
                        echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
                        dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1
                        systemctl enable --now unattended-upgrades >/dev/null 2>&1
                        echo -e "${GREEN}✅ 系统自动安全更新已开启！${PLAIN}"
                    fi
                elif [[ "$OS" =~ centos|rhel|rocky|almalinux ]]; then
                    if [[ "$update_status" == "active" ]]; then
                        systemctl disable --now dnf-automatic.timer >/dev/null 2>&1
                        echo -e "${GREEN}✅ 系统自动安全更新已禁用！${PLAIN}"
                    else
                        yum install -y dnf-automatic -q >/dev/null 2>&1
                        systemctl enable --now dnf-automatic.timer >/dev/null 2>&1
                        echo -e "${GREEN}✅ 系统自动安全更新已开启！${PLAIN}"
                    fi
                fi
                sleep 1 ;;
            4)
                echo -e "${CYAN}👉 正在清理系统垃圾...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then apt autoremove --purge -y >/dev/null 2>&1; apt clean >/dev/null 2>&1
                else yum autoremove -y >/dev/null 2>&1; yum clean all >/dev/null 2>&1; fi
                journalctl --vacuum-time=1d > /dev/null 2>&1
                history -c
                echo -e "${GREEN}✅ 系统垃圾清理完成，空间已释放！${PLAIN}"; sleep 1 ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 3. 常用环境一键安装
# ---------------------------------------------------------
func_env_install() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📦 常用运行环境一键安装${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 安装 Python3 & Pip${PLAIN}"
        echo -e "${GREEN}  2. 安装 Node.js (LTS版本)${PLAIN}"
        echo -e "${GREEN}  3. 安装 Golang (最新版)${PLAIN}"
        echo -e "${GREEN}  4. 安装 Java (OpenJDK 17)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择环境安装: " env_choice
        case $env_choice in
            1)
                echo -e "${CYAN}👉 安装 Python3 & Pip...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then apt install -y python3 python3-pip >/dev/null 2>&1; else yum install -y python3 python3-pip >/dev/null 2>&1; fi
                python3 -V && pip3 -V; echo -e "${GREEN}✅ 安装完成！${PLAIN}"; read -n 1 -s -r -p "按任意键返回..." ;;
            2)
                echo -e "${CYAN}👉 安装 Node.js...${PLAIN}"
                curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >/dev/null 2>&1
                if [[ "$OS" =~ debian|ubuntu ]]; then apt install -y nodejs >/dev/null 2>&1; else yum install -y nodejs >/dev/null 2>&1; fi
                node -v && npm -v; echo -e "${GREEN}✅ 安装完成！${PLAIN}"; read -n 1 -s -r -p "按任意键返回..." ;;
            3)
                echo -e "${CYAN}👉 安装 Golang...${PLAIN}"
                wget -qO go.tar.gz https://go.dev/dl/go1.22.1.linux-amd64.tar.gz
                rm -rf /usr/local/go && tar -C /usr/local -xzf go.tar.gz && rm go.tar.gz
                echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
                source /etc/profile.d/go.sh
                /usr/local/go/bin/go version; echo -e "${GREEN}✅ 安装完成！请在重启终端后生效。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..." ;;
            4)
                echo -e "${CYAN}👉 安装 OpenJDK 17...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then apt install -y openjdk-17-jdk >/dev/null 2>&1; else yum install -y java-17-openjdk >/dev/null 2>&1; fi
                java -version; echo -e "${GREEN}✅ 安装完成！${PLAIN}"; read -n 1 -s -r -p "按任意键返回..." ;;
            0) break ;;
        esac
    done
}

# ---------------------------------------------------------
# 4. SSH 安全加固 (端口 + Fail2ban)
# ---------------------------------------------------------
func_security() {
    clear
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
    echo -e "${GREEN}✅ Fail2ban 防暴力破解已生效！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 5. Docker 深度管理面板
# ---------------------------------------------------------
func_docker_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🐳 Docker 深度管理面板${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        if command -v docker >/dev/null 2>&1; then
            dk_status="${GREEN}已安装${PLAIN} ($(docker -v | awk '{print $3}' | tr -d ','))"
        else
            dk_status="${RED}未安装${PLAIN}"
        fi

        echo -e "Docker 当前状态: $dk_status"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 一键安装 Docker 环境${PLAIN}"
        echo -e "${GREEN}  2. 一键卸载 Docker${PLAIN}       (保留容器数据)"
        echo -e "${GREEN}  3. 开启 Docker 本地防穿透保护${PLAIN} (限制仅 127.0.0.1 访问)"
        echo -e "${GREEN}  4. 解除 Docker 本地防穿透保护${PLAIN} (允许 0.0.0.0 全网访问)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择操作: " dk_choice

        case $dk_choice in
            1)
                echo -e "${CYAN}👉 正在调用官方脚本安装 Docker...${PLAIN}"
                curl -fsSL https://get.docker.com | bash
                systemctl enable --now docker > /dev/null 2>&1
                echo -e "${GREEN}✅ Docker 安装完成！${PLAIN}"; sleep 1 ;;
            2)
                echo -e "${CYAN}👉 正在卸载 Docker...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then apt purge -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1; else yum remove -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1; fi
                echo -e "${GREEN}✅ Docker 引擎已卸载。${PLAIN}"; sleep 1 ;;
            3)
                mkdir -p /etc/docker
                cat <<EOF > /etc/docker/daemon.json
{
    "ip": "127.0.0.1",
    "log-driver": "json-file",
    "log-opts": { "max-size": "50m", "max-file": "3" }
}
EOF
                systemctl daemon-reload && systemctl restart docker
                echo -e "${GREEN}✅ 本地防穿透与日志限制保护已开启！${PLAIN}"; sleep 1 ;;
            4)
                if [ -f /etc/docker/daemon.json ]; then rm -f /etc/docker/daemon.json; fi
                systemctl daemon-reload && systemctl restart docker
                echo -e "${GREEN}✅ 已解除本地防穿透限制！${PLAIN}"; sleep 1 ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 6. BBR 加速管理面板
# ---------------------------------------------------------
func_bbr_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🚀 BBR 拥塞控制算法管理面板${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        current_bbr=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
        current_qdisc=$(sysctl net.core.default_qdisc | awk '{print $3}')
        
        echo -e "当前算法: ${GREEN}${current_bbr}${PLAIN} | 队列控制: ${GREEN}${current_qdisc}${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 开启 BBR 原生版${PLAIN} (适用所有机器，推荐)"
        echo -e "${GREEN}  2. 切换回 Cubic 算法${PLAIN} (关闭 BBR 加速)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择操作: " bbr_choice

        case $bbr_choice in
            1)
                echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-bbr.conf
                echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-bbr.conf
                sysctl -p /etc/sysctl.d/99-bbr.conf > /dev/null 2>&1
                echo -e "${GREEN}✅ 原生 BBR 加速已开启！${PLAIN}"; sleep 1 ;;
            2)
                echo "net.core.default_qdisc = pfifo_fast" > /etc/sysctl.d/99-bbr.conf
                echo "net.ipv4.tcp_congestion_control = cubic" >> /etc/sysctl.d/99-bbr.conf
                sysctl -p /etc/sysctl.d/99-bbr.conf > /dev/null 2>&1
                echo -e "${GREEN}✅ 已关闭 BBR，恢复默认 Cubic 算法。${PLAIN}"; sleep 1 ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 7. 动态 TCP 调优 (Omnitt)
# ---------------------------------------------------------
func_tcp_tune() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🌐 动态 TCP 网络调优 (由 Omnitt 强力驱动)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}请在浏览器中打开以下网站，生成您的专属配置：${PLAIN}\n"
    echo -e "${BOLD}${BLUE}👉 https://omnitt.com/ ${PLAIN}\n"
    read -p "👉 生成并复制好参数了吗？(回车继续，输入 n 取消): " start_paste
    if [[ -n "$start_paste" ]] && [[ ! "$start_paste" =~ ^[Yy]$ ]]; then return; fi

    echo -e "\n${CYAN}👇 请在此处右键粘贴代码，完成后在新行输入 EOF 并按回车：${PLAIN}"
    temp_file="/etc/sysctl.d/99-omnitt-tune.conf"
    > "$temp_file"
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r')
        if [[ "$line" == "EOF" || "$line" == "eof" ]]; then break; fi
        echo "$line" >> "$temp_file"
    done
    if [ -s "$temp_file" ]; then
        apply_sysctl "$temp_file"
        echo -e "${GREEN}✅ 定制 TCP 网络调优已成功应用！${PLAIN}"
    else
        rm -f "$temp_file"
        echo -e "${YELLOW}⚠️ 未检测到有效参数，已取消。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 8. 智能内存调优 (ZRAM + Swap)
# ---------------------------------------------------------
func_zram_swap() {
    clear
    mem_total=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$mem_total" -le 1536 ]; then rec_zram=100; rec_swap=100; rec_vfs=50; 
    elif [ "$mem_total" -le 6144 ]; then rec_zram=70; rec_swap=60; rec_vfs=50; 
    else rec_zram=25; rec_swap=10; rec_vfs=100; fi

    echo -e "${CYAN}💡 算法推荐: ZRAM ${rec_zram}%, Swappiness ${rec_swap}${PLAIN}"
    read -p "是否应用推荐方案？(回车默认, n 手动): " use_rec
    if [[ -z "$use_rec" || "$use_rec" =~ ^[Yy]$ ]]; then
        final_zram=$rec_zram; final_swap=$rec_swap; final_vfs=$rec_vfs
    else
        read -p "请选择 [1.激进 2.积极 3.保守]: " manual_choice
        case $manual_choice in 1) final_zram=100; final_swap=100; final_vfs=50;; 2) final_zram=70; final_swap=60; final_vfs=50;; 3) final_zram=25; final_swap=10; final_vfs=100;; *) final_zram=70; final_swap=60; final_vfs=50;; esac
    fi

    if [[ "$OS" =~ debian|ubuntu ]]; then
        apt update -y -qq && apt install -y zram-tools -qq
        echo -e "ALGO=zstd\nPERCENT=$final_zram\nPRIORITY=100" > /etc/default/zramswap
        systemctl restart zramswap > /dev/null 2>&1
    fi
    if [ ! -f /swapfile ]; then
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
        chmod 600 /swapfile && mkswap /swapfile > /dev/null 2>&1 && swapon --priority -2 /swapfile
        grep -q "/swapfile" /etc/fstab || echo '/swapfile none swap sw,pri=-2 0 0' >> /etc/fstab
    fi

    echo "vm.swappiness=$final_swap" > /etc/sysctl.d/99-memory-tune.conf
    [[ "$final_vfs" == "50" ]] && echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-memory-tune.conf
    sysctl -p /etc/sysctl.d/99-memory-tune.conf > /dev/null 2>&1
    echo -e "${GREEN}✅ 智能内存调优已完成！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 9. Cloud内核 / 10. 清理旧内核
# ---------------------------------------------------------
func_install_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then echo -e "${RED}❌ 仅支持 Debian/Ubuntu。${PLAIN}"; else
        apt update -y && apt install -y linux-image-cloud-amd64
        echo -e "${GREEN}✅ Cloud 内核安装完成！请重启加载。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

func_clean_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then echo -e "${RED}❌ 仅支持 Debian/Ubuntu。${PLAIN}"; else
        echo -e "${YELLOW}当前正在运行的内核: $(uname -r)${PLAIN}\n"
        dpkg --list | grep linux-image
        echo -e "\n${RED}🔴 警告：请勿卸载带有 'cloud' 及当前运行的内核！${PLAIN}"
        read -p "✍️ 请输入要卸载的旧内核包名 (回车取消): " old_kernels
        if [ -n "$old_kernels" ]; then
            apt purge -y $old_kernels && update-grub && apt autoremove --purge -y
            echo -e "${GREEN}✅ 旧内核已彻底清理！${PLAIN}"
        fi
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 11. 硬件探针 / 12. 测速 / 13. 流量狗
# ---------------------------------------------------------
func_system_info() {
    clear
    os_name=$(cat /etc/os-release | grep -w "PRETTY_NAME" | cut -d= -f2 | tr -d '"')
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}系统 OS  :${PLAIN} $os_name ($(uname -m))"
    echo -e "${YELLOW}内核版本 :${PLAIN} $(uname -r) | 虚拟化: $(systemd-detect-virt 2>/dev/null || echo "未知")"
    echo -e "${YELLOW}CPU 信息 :${PLAIN} $(nproc) 核心 | $(lscpu | grep "Model name:" | sed 's/Model name:\s*//')"
    echo -e "${YELLOW}内存占用 :${PLAIN} $(free -h | awk '/^Mem:/ {print $3}') / $(free -h | awk '/^Mem:/ {print $2}')"
    echo -e "${YELLOW}硬盘占用 :${PLAIN} $(df -h / | awk 'NR==2 {print $3}') / $(df -h / | awk 'NR==2 {print $2}')"
    echo -e "${YELLOW}IPv4 地址:${PLAIN} $(curl -s4 --max-time 3 ipv4.icanhazip.com || echo "无")"
    echo -e "${YELLOW}IPv6 地址:${PLAIN} $(curl -s6 --max-time 3 ipv6.icanhazip.com || echo "无")"
    echo -e "${CYAN}================================================${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..."
}

func_test_scripts() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📊 VPS 综合测试脚本合集${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. YABS 综合测试 ${YELLOW}(性能/硬盘/国际带宽，最权威)${PLAIN}"
        echo -e "${GREEN}  2. SuperBench    ${YELLOW}(系统信息 + 国内三网节点测速)${PLAIN}"
        echo -e "${GREEN}  3. 三网回程路由  ${YELLOW}(NextTrace 高级可视化路由节点)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择测试项目: " test_choice
        case $test_choice in
            1) wget -qO- yabs.sh | bash ;;
            2) wget -qO- about.superbench.pro | bash ;;
            3) curl nxtrace.org/nt | bash ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ; sleep 1 ;;
        esac
        echo ""; read -n 1 -s -r -p "按任意键返回测试菜单..."
    done
}

func_traffic_dog() {
    clear
    echo -e "${CYAN}👉 正在拉取运行端口流量狗...${PLAIN}"
    wget -qO port-traffic-dog.sh https://raw.githubusercontent.com/zywe03/realm-xwPF/main/port-traffic-dog.sh
    if [ -f "port-traffic-dog.sh" ]; then chmod +x port-traffic-dog.sh && ./port-traffic-dog.sh; fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 14. Xray / 15. Singbox
# ---------------------------------------------------------
func_xray_panel() {
    clear
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    read -n 1 -s -r -p "按任意键返回..."
}
func_singbox_yg() {
    clear
    bash <(curl -fsSL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 界面主循环 (深度分类排版)
# ---------------------------------------------------------
main_menu() {
    create_shortcut
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🚀 VPS 终极全能控制面板 (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}${BLUE} 【基础与环境】${PLAIN}"
        echo -e "${GREEN}   1. 基础环境初始化 ${YELLOW}(修复并开启默认 BBR 加速)${PLAIN}"
        echo -e "${GREEN}   2. 系统高级开关   ${YELLOW}(⚙️ 自动更新/IPv6/防Ping)${PLAIN}"
        echo -e "${GREEN}   3. 常用环境安装   ${YELLOW}(📦 Node.js/Python/Go/Java)${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${BOLD}${BLUE} 【安全与网络】${PLAIN}"
        echo -e "${GREEN}   4. SSH 安全加固   ${YELLOW}(修改默认端口/防爆破拦截)${PLAIN}"
        echo -e "${GREEN}   5. Docker 管理    ${YELLOW}(🐳 安装卸载/配置安全防穿透)${PLAIN}"
        echo -e "${GREEN}   6. BBR 加速管理   ${YELLOW}(🚀 查看状态/切换拥塞控制算法)${PLAIN}"
        echo -e "${GREEN}   7. 动态 TCP 调优  ${YELLOW}(🔗 联动 Omnitt 生成防呆参数)${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${BOLD}${BLUE} 【内核与内存】${PLAIN}"
        echo -e "${GREEN}   8. 智能内存调优   ${YELLOW}(自适应配置 ZRAM压缩 + Swap)${PLAIN}"
        echo -e "${GREEN}   9. 换装 Cloud内核 ${YELLOW}(释放硬件驱动，KVM 专属)${PLAIN}"
        echo -e "${GREEN}  10. 卸载冗余旧内核 ${YELLOW}(释放 /boot 空间，需谨慎)${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${BOLD}${BLUE} 【探针与节点】${PLAIN}"
        echo -e "${GREEN}  11. 极速硬件探针   ${YELLOW}(查看本机配置与实时占用)${PLAIN}"
        echo -e "${GREEN}  12. 综合测试合集   ${YELLOW}(YABS / 国内三网测速 / 路由)${PLAIN}"
        echo -e "${GREEN}  13. 端口流量监控   ${YELLOW}(拉取运行 Port Traffic Dog)${PLAIN}"
        echo -e "${GREEN}  14. 安装新版 Xray  ${YELLOW}(调用 3x-ui 面板官方脚本)${PLAIN}"
        echo -e "${GREEN}  15. 安装 Sing-box  ${YELLOW}(调用勇哥四合一官方脚本)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${RED}  16. 重启系统       ${YELLOW}(使各项内核参数彻底生效)${PLAIN}"
        echo -e "${RED}   0. 退出面板${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请输入数字选择功能: " choice

        case $choice in
            1) func_base_init ;;
            2) func_system_tweaks ;;
            3) func_env_install ;;
            4) func_security ;;
            5) func_docker_manage ;;
            6) func_bbr_manage ;;
            7) func_tcp_tune ;;
            8) func_zram_swap ;;
            9) func_install_kernel ;;
            10) func_clean_kernel ;;
            11) func_system_info ;;
            12) func_test_scripts ;;
            13) func_traffic_dog ;;
            14) func_xray_panel ;;
            15) func_singbox_yg ;;
            16) 
                read -p "⚠️ 确定要重启服务器吗？(y/n): " confirm_reboot
                [[ "$confirm_reboot" =~ ^[Yy]$ ]] && reboot ;;
            0) 
                clear; echo -e "${GREEN}👋 感谢使用！记得随时输入 'cy' 唤出面板。${PLAIN}"; exit 0 ;;
            *) 
                echo -e "${RED}❌ 无效的输入！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# 启动主程序
main_menu
