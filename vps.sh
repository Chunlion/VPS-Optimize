#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 终极全能控制面板 (严谨交互完整版)
#  Features: y/n强交互/UFW防火墙/测试合集/面板/BBR/内核
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
# 1. 基础环境与工具初始化
# ---------------------------------------------------------
func_base_init() {
    clear
    echo -e "${CYAN}👉 正在安装常用工具、限制系统日志并开启基础 BBR...${PLAIN}"
    if [[ "$OS" =~ debian|ubuntu ]]; then
        apt update -qq && apt install -y curl wget git nano unzip htop iptables -qq > /dev/null 2>&1
    elif [[ "$OS" =~ centos|rhel|rocky|almalinux ]]; then
        yum install -y curl wget git nano unzip htop iptables epel-release -q > /dev/null 2>&1
    fi

    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/99-limit.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF
    systemctl restart systemd-journald > /dev/null 2>&1
    timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1
    
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-bbr-init.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-bbr-init.conf
    sysctl -p /etc/sysctl.d/99-bbr-init.conf > /dev/null 2>&1
    
    echo -e "${GREEN}✅ 基础工具安装完毕，时区已同步，系统默认 BBR 已激活！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 2. 系统高级开关 (防Ping/IPv6/自动更新/防火墙 - 智能端口嗅探)
# ---------------------------------------------------------
func_system_tweaks() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}⚙️  系统高级开关与清理优化 (输入 y 开启, n 关闭)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        # 状态获取
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
        if [[ "$ipv6_status" == "0" ]]; then str_ipv6="${GREEN}开启中${PLAIN}"; else str_ipv6="${RED}已禁用${PLAIN}"; fi
        
        ping_status=$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null)
        if [[ "$ping_status" == "0" ]]; then str_ping="${GREEN}允许被Ping${PLAIN}"; else str_ping="${RED}禁Ping中${PLAIN}"; fi

        if [[ "$OS" =~ debian|ubuntu ]]; then
            update_status=$(systemctl is-active unattended-upgrades 2>/dev/null)
            fw_status=$(ufw status 2>/dev/null | grep -wi active)
            if [[ -n "$fw_status" ]]; then str_fw="${GREEN}开启中 (UFW)${PLAIN}"; else str_fw="${RED}已禁用/未安装${PLAIN}"; fi
        else
            update_status=$(systemctl is-active dnf-automatic.timer 2>/dev/null)
            fw_status=$(systemctl is-active firewalld 2>/dev/null)
            if [[ "$fw_status" == "active" ]]; then str_fw="${GREEN}开启中 (Firewalld)${PLAIN}"; else str_fw="${RED}已禁用/未安装${PLAIN}"; fi
        fi
        if [[ "$update_status" == "active" ]]; then str_update="${GREEN}开启中${PLAIN}"; else str_update="${RED}已禁用${PLAIN}"; fi

        echo -e "${GREEN}  1. 管理 IPv6 网络状态${PLAIN}    当前: [ $str_ipv6 ]"
        echo -e "${GREEN}  2. 管理 被人Ping状态${PLAIN}     当前: [ $str_ping ]"
        echo -e "${GREEN}  3. 管理 自动安全更新${PLAIN}     当前: [ $str_update ]"
        echo -e "${GREEN}  4. 管理 系统安全防火墙${PLAIN}   当前: [ $str_fw ]"
        echo -e "${GREEN}  5. 彻底清理系统垃圾${PLAIN}      (清空无用包、日志、缓存)"
        echo -e "${GREEN}  6. 查看防火墙端口规则${PLAIN}    (查看当前已放行的白名单)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择操作: " tweak_choice

        case $tweak_choice in
            1)
                read -p "❓ 是否开启 IPv6 网络？(y 开启 / n 关闭): " yn_choice
                if [[ "$yn_choice" =~ ^[Yy]$ ]]; then
                    rm -f /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null 2>&1
                    echo -e "${GREEN}✅ IPv6 已开启！${PLAIN}"
                elif [[ "$yn_choice" =~ ^[Nn]$ ]]; then
                    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf
                    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf > /dev/null 2>&1
                    echo -e "${GREEN}✅ IPv6 已禁用！${PLAIN}"
                fi; sleep 1 ;;
            2)
                read -p "❓ 是否允许服务器被 Ping？(y 允许 / n 禁止): " yn_choice
                if [[ "$yn_choice" =~ ^[Yy]$ ]]; then
                    rm -f /etc/sysctl.d/99-disable-ping.conf
                    sysctl -w net.ipv4.icmp_echo_ignore_all=0 > /dev/null 2>&1
                    echo -e "${GREEN}✅ 已允许服务器被 Ping！${PLAIN}"
                elif [[ "$yn_choice" =~ ^[Nn]$ ]]; then
                    echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf
                    sysctl -p /etc/sysctl.d/99-disable-ping.conf > /dev/null 2>&1
                    echo -e "${GREEN}✅ 已开启禁 Ping 保护！${PLAIN}"
                fi; sleep 1 ;;
            3)
                read -p "❓ 是否开启系统自动安全更新？(y 开启 / n 关闭): " yn_choice
                if [[ "$yn_choice" =~ ^[Yy]$ ]]; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        apt install -y unattended-upgrades -qq >/dev/null 2>&1
                        echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
                        dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1
                        systemctl enable --now unattended-upgrades >/dev/null 2>&1
                    else
                        yum install -y dnf-automatic -q >/dev/null 2>&1
                        systemctl enable --now dnf-automatic.timer >/dev/null 2>&1
                    fi
                    echo -e "${GREEN}✅ 系统自动更新已开启！${PLAIN}"
                elif [[ "$yn_choice" =~ ^[Nn]$ ]]; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then systemctl disable --now unattended-upgrades >/dev/null 2>&1
                    else systemctl disable --now dnf-automatic.timer >/dev/null 2>&1; fi
                    echo -e "${GREEN}✅ 系统自动更新已关闭！${PLAIN}"
                fi; sleep 1 ;;
            4)
                read -p "❓ 是否开启系统防火墙？(y 开启 / n 关闭): " yn_choice
                if [[ "$yn_choice" =~ ^[Yy]$ ]]; then
                    echo -e "${CYAN}👉 正在嗅探当前系统已暴露的活动端口...${PLAIN}"
                    # 智能获取所有处于 LISTEN (TCP) 和 UNCONN (UDP) 状态的端口，并排除 127.0.0.1 内部通信
                    active_ports=$(ss -tuln | grep -E 'LISTEN|UNCONN' | grep -v '127.0.0.1' | grep -v '::1' | awk '{print $5}' | rev | cut -d: -f1 | rev | sort -nu | grep -E '^[0-9]+$')
                    
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        apt install ufw -y >/dev/null 2>&1
                        ufw default deny incoming >/dev/null 2>&1
                        ufw default allow outgoing >/dev/null 2>&1
                        
                        # 遍历并放行所有智能检测到的端口
                        for port in $active_ports; do
                            ufw allow $port >/dev/null 2>&1
                            echo -e "${GREEN}✅ 检测并放行端口: $port (UFW)${PLAIN}"
                        done
                        
                        ufw --force enable >/dev/null 2>&1
                    else
                        yum install firewalld -y >/dev/null 2>&1
                        systemctl enable --now firewalld >/dev/null 2>&1
                        
                        # 遍历并放行所有智能检测到的端口
                        for port in $active_ports; do
                            firewall-cmd --permanent --add-port=${port}/tcp >/dev/null 2>&1
                            firewall-cmd --permanent --add-port=${port}/udp >/dev/null 2>&1
                            echo -e "${GREEN}✅ 检测并放行端口: $port (Firewalld)${PLAIN}"
                        done
                        firewall-cmd --reload >/dev/null 2>&1
                    fi
                    echo -e "${GREEN}✅ 防火墙已成功开启！基础策略(阻入放出)与动态放行已生效。${PLAIN}"
                elif [[ "$yn_choice" =~ ^[Nn]$ ]]; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then ufw disable >/dev/null 2>&1
                    else systemctl disable --now firewalld >/dev/null 2>&1; fi
                    echo -e "${GREEN}✅ 防火墙已关闭！${PLAIN}"
                fi; read -n 1 -s -r -p "按任意键继续..." ;;
            5)
                echo -e "${CYAN}👉 正在清理系统垃圾...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then apt autoremove --purge -y >/dev/null 2>&1; apt clean >/dev/null 2>&1
                else yum autoremove -y >/dev/null 2>&1; yum clean all >/dev/null 2>&1; fi
                journalctl --vacuum-time=1d > /dev/null 2>&1
                history -c
                echo -e "${GREEN}✅ 垃圾清理完成！${PLAIN}"; sleep 1 ;;
            6)
                clear
                echo -e "${CYAN}================================================${PLAIN}"
                echo -e "${BOLD}🛡️ 当前防火墙放行规则与端口状态${PLAIN}"
                echo -e "${CYAN}================================================${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    if command -v ufw >/dev/null 2>&1; then
                        ufw status verbose
                    else
                        echo -e "${RED}未安装或未启用 UFW 防火墙。${PLAIN}"
                    fi
                else
                    if command -v firewall-cmd >/dev/null 2>&1; then
                        firewall-cmd --list-all
                    else
                        echo -e "${RED}未安装或未启用 Firewalld 防火墙。${PLAIN}"
                    fi
                fi
                echo ""
                read -n 1 -s -r -p "按任意键返回..." ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ; sleep 1 ;;
        esac
    done
}
# ---------------------------------------------------------
# 3. 常用环境及软件一键安装 
# ---------------------------------------------------------
func_env_install() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📦 常用环境及全能软件一键安装库${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. Docker 引擎   ${YELLOW}(官方一键脚本)${PLAIN}"
        echo -e "${GREEN}  2. Python 环境   ${YELLOW}(lxspacepy 自动脚本)${PLAIN}"
        echo -e "${GREEN}  3. iperf3 工具   ${YELLOW}(网络吞吐量测速神器)${PLAIN}"
        echo -e "${GREEN}  4. Realm 转发    ${YELLOW}(端口转发神器)${PLAIN}"
        echo -e "${GREEN}  5. Gost 隧道     ${YELLOW}(EZgost 加密隧道转发)${PLAIN}"
        echo -e "${GREEN}  6. 极光面板      ${YELLOW}(Aurora 多服务器流量管理)${PLAIN}"
        echo -e "${GREEN}  7. 哪吒监控      ${YELLOW}(Nezha 探针面板端/被控端)${PLAIN}"
        echo -e "${GREEN}  8. WARP (CF)     ${YELLOW}(fscarmen 官方菜单脚本)${PLAIN}"
        echo -e "${GREEN}  9. Aria2 下载    ${YELLOW}(增强版一键下载工具)${PLAIN}"
        echo -e "${GREEN} 10. 宝塔面板      ${YELLOW}(HostCLI 定制优化版)${PLAIN}"
        echo -e "${GREEN} 11. PVE 虚拟化    ${YELLOW}(Debian一键安装后端环境)${PLAIN}"
        echo -e "${GREEN} 12. Argox 节点    ${YELLOW}(fscarmen Argo 穿透节点)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择环境安装: " env_choice
        case $env_choice in
            1) bash <(curl -sL 'https://get.docker.com') ;;
            2) curl -O https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh && chmod +x pyinstall.sh && ./pyinstall.sh ;;
            3) if [[ "$OS" =~ debian|ubuntu ]]; then apt install -y iperf3; else yum install -y epel-release && yum install -y iperf3; fi; echo -e "${GREEN}✅ iperf3 安装完成！${PLAIN}" ;;
            4) bash <(curl -L https://raw.githubusercontent.com/zhouh047/realm-oneclick-install/main/realm.sh) -i ;;
            5) wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh && chmod +x gost.sh && ./gost.sh ;;
            6) bash <(curl -fsSL https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh) ;;
            7) 
                curl -L https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh -o nezha.sh && chmod +x nezha.sh && sudo ./nezha.sh
                echo -e "\n${YELLOW}💡 【设置自定义代码去动画提示】：${PLAIN}"
                echo -e "${GREEN}<script>\nwindow.ShowNetTransfer = true;\nwindow.FixedTopServerName = true;\nwindow.DisableAnimatedMan = true;\n</script>${PLAIN}"
                ;;
            8) wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh ;;
            9) wget -N git.io/aria2.sh && chmod +x aria2.sh && ./aria2.sh ;;
            10) wget -O install.sh http://v7.hostcli.com/install/install-ubuntu_6.0.sh && sudo bash install.sh ;;
            11) bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh) ;;
            12) bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh) ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac
        echo ""; read -n 1 -s -r -p "按任意键返回环境安装菜单..."
    done
}

# ---------------------------------------------------------
# 4. SSH 安全加固 (包含极其严谨的三重防火墙放行逻辑)
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
        
        # 三重保险：自动放行新端口，防止失联
        if command -v ufw >/dev/null 2>&1; then ufw allow "$final_port"/tcp >/dev/null; fi
        if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --permanent --add-port="$final_port"/tcp >/dev/null; firewall-cmd --reload >/dev/null; fi
        iptables -I INPUT -p tcp --dport "$final_port" -j ACCEPT 2>/dev/null
        iptables-save >/dev/null 2>&1
        
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        echo -e "${GREEN}✅ SSH 端口已修改为: $final_port 并已成功放行防火墙！${PLAIN}"
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
# 5. Docker 深度管理 
# ---------------------------------------------------------
func_docker_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🐳 Docker 深度管理面板${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        if command -v docker >/dev/null 2>&1; then dk_status="${GREEN}已安装${PLAIN} ($(docker -v | awk '{print $3}' | tr -d ','))"; else dk_status="${RED}未安装${PLAIN}"; fi
        echo -e "Docker 当前状态: $dk_status"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 一键卸载 Docker${PLAIN}       (保留容器数据)"
        echo -e "${GREEN}  2. 开启 Docker 本地防穿透保护${PLAIN} (限制仅 127.0.0.1 访问)"
        echo -e "${GREEN}  3. 解除 Docker 本地防穿透保护${PLAIN} (允许 0.0.0.0 全网访问)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择操作: " dk_choice
        case $dk_choice in
            1) if [[ "$OS" =~ debian|ubuntu ]]; then apt purge -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1; else yum remove -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1; fi; echo -e "${GREEN}✅ Docker 引擎已卸载。${PLAIN}"; sleep 1 ;;
            2) mkdir -p /etc/docker; cat <<EOF > /etc/docker/daemon.json
{ "ip": "127.0.0.1", "log-driver": "json-file", "log-opts": { "max-size": "50m", "max-file": "3" } }
EOF
            systemctl daemon-reload && systemctl restart docker; echo -e "${GREEN}✅ 本地防穿透与日志限制保护已开启！${PLAIN}"; sleep 1 ;;
            3) if [ -f /etc/docker/daemon.json ]; then rm -f /etc/docker/daemon.json; fi; systemctl daemon-reload && systemctl restart docker; echo -e "${GREEN}✅ 已解除本地防穿透限制！${PLAIN}"; sleep 1 ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 6. BBR 加速管理面板
# ---------------------------------------------------------
func_bbr_manage() {
    clear
    echo -e "${CYAN}👉 正在拉取执行全能 BBR 管理脚本...${PLAIN}"
    wget -O tcpx.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
    echo ""
    read -n 1 -s -r -p "按任意键返回主菜单..."
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
    if [ -s "$temp_file" ]; then apply_sysctl "$temp_file"; echo -e "${GREEN}✅ 定制 TCP 网络调优已成功应用！${PLAIN}"; else rm -f "$temp_file"; echo -e "${YELLOW}⚠️ 未检测到有效参数，已取消。${PLAIN}"; fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 8. 智能内存调优 (新增详尽策略解释)
# ---------------------------------------------------------
func_zram_swap() {
    clear
    mem_total=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$mem_total" -le 1536 ]; then rec_zram=100; rec_swap=100; rec_vfs=50; 
    elif [ "$mem_total" -le 6144 ]; then rec_zram=70; rec_swap=60; rec_vfs=50; 
    else rec_zram=25; rec_swap=10; rec_vfs=100; fi

    echo -e "${CYAN}💡 算法推荐 (基于本机 ${mem_total}MB 物理内存): ZRAM ${rec_zram}%, Swappiness ${rec_swap}${PLAIN}"
    read -p "是否应用系统推荐方案？(回车默认应用, 输入 n 手动选择): " use_rec
    
    if [[ -z "$use_rec" || "$use_rec" =~ ^[Yy]$ ]]; then
        final_zram=$rec_zram; final_swap=$rec_swap; final_vfs=$rec_vfs
    else
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}【配置策略详解】${PLAIN}"
        echo -e " ${GREEN}1. 激进型${PLAIN}: 适合 1GB 以下内存。牺牲 CPU 极限压缩内存，极其倾向使用硬盘 Swap 防崩溃。"
        echo -e " ${GREEN}2. 积极型${PLAIN}: 适合 2-4GB 内存。主流平衡配置，划出 70% 用于压缩，中度使用硬盘 Swap。"
        echo -e " ${GREEN}3. 保守型${PLAIN}: 适合 8GB 以上内存。少用 ZRAM (25%)，且尽全力避免读取硬盘 Swap 以保证高速度。"
        echo -e "------------------------------------------------"
        read -p "👉 请选择您的策略 [1/2/3]: " manual_choice
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
        if [ -n "$old_kernels" ]; then apt purge -y $old_kernels && update-grub && apt autoremove --purge -y; echo -e "${GREEN}✅ 旧内核已彻底清理！${PLAIN}"; fi
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 11. 硬件探针
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

# ---------------------------------------------------------
# 12. 综合测试脚本合集 (史诗级扩充)
# ---------------------------------------------------------
func_test_scripts() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📊 VPS 综合测试神级合集库${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. YABS 性能测试   ${YELLOW}(CPU/硬盘/国际带宽极速测试)${PLAIN}"
        echo -e "${GREEN}  2. 融合怪 终极测速 ${YELLOW}(全球最全的性能/流媒体/线路测试)${PLAIN}"
        echo -e "${GREEN}  3. SuperBench      ${YELLOW}(经典系统信息 + 国内三网测速)${PLAIN}"
        echo -e "${GREEN}  4. bench.sh        ${YELLOW}(秋水逸冰基础 IO 与国外测速)${PLAIN}"
        echo -e "${GREEN}  5. 流媒体解锁检测  ${YELLOW}(Netflix/Youtube/Disney+ 检测)${PLAIN}"
        echo -e "${GREEN}  6. 三网回程路由    ${YELLOW}(NextTrace 节点到国内动态路由)${PLAIN}"
        echo -e "${GREEN}  7. 欺诈 IP 质量检测${YELLOW}(检测 IP 是否为原生/被识别为机房)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择测试项目: " test_choice
        case $test_choice in
            1) wget -qO- yabs.sh | bash ;;
            2) curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && bash ecs.sh ;;
            3) wget -qO- about.superbench.pro | bash ;;
            4) wget -qO- bench.sh | bash ;;
            5) bash <(curl -L -s check.unlock.media) ;;
            6) curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh ;;
            7) bash <(curl -Ls IP.Check.Place) ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ; sleep 1 ;;
        esac
        echo ""; read -n 1 -s -r -p "按任意键返回测试菜单..."
    done
}

# ---------------------------------------------------------
# 13. 流量监控 / 14-15 面板
# ---------------------------------------------------------
func_traffic_dog() {
    clear
    wget -qO port-traffic-dog.sh https://raw.githubusercontent.com/zywe03/realm-xwPF/main/port-traffic-dog.sh
    if [ -f "port-traffic-dog.sh" ]; then chmod +x port-traffic-dog.sh && ./port-traffic-dog.sh; fi
    read -n 1 -s -r -p "按任意键返回..."
}
func_xray_panel() {
    clear
    bash <(curl -Ls https://raw.githubusercontent.com/xeefei/x-panel/master/install.sh)
    read -n 1 -s -r -p "按任意键返回..."
}
func_singbox_yg() {
    clear
    bash <(curl -fsSL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 界面主循环
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
        echo -e "${GREEN}   2. 系统高级开关   ${YELLOW}(⚙️ 防火墙/自动更新/IPv6/防Ping)${PLAIN}"
        echo -e "${GREEN}   3. 常用环境与软件 ${YELLOW}(📦 宝塔/探针/WARP/路由等)${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${BOLD}${BLUE} 【安全与网络】${PLAIN}"
        echo -e "${GREEN}   4. SSH 安全加固   ${YELLOW}(改端口防爆破/自动放行防火墙)${PLAIN}"
        echo -e "${GREEN}   5. Docker 管理    ${YELLOW}(🐳 安装卸载/配置安全防穿透)${PLAIN}"
        echo -e "${GREEN}   6. BBR 加速管理   ${YELLOW}(🚀 调用外部全能 BBR 管理脚本)${PLAIN}"
        echo -e "${GREEN}   7. 动态 TCP 调优  ${YELLOW}(🔗 联动 Omnitt 生成防呆参数)${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${BOLD}${BLUE} 【内核与内存】${PLAIN}"
        echo -e "${GREEN}   8. 智能内存调优   ${YELLOW}(含激进/保守多档位详细解释)${PLAIN}"
        echo -e "${GREEN}   9. 换装 Cloud内核 ${YELLOW}(释放硬件驱动，KVM 专属)${PLAIN}"
        echo -e "${GREEN}  10. 卸载冗余旧内核 ${YELLOW}(释放 /boot 空间，需谨慎)${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${BOLD}${BLUE} 【探针与节点】${PLAIN}"
        echo -e "${GREEN}  11. 极速硬件探针   ${YELLOW}(查看本机配置与实时占用)${PLAIN}"
        echo -e "${GREEN}  12. 综合测试合集   ${YELLOW}(融合怪 / 流媒体 / 欺诈IP检测)${PLAIN}"
        echo -e "${GREEN}  13. 端口流量监控   ${YELLOW}(拉取运行 Port Traffic Dog)${PLAIN}"
        echo -e "${GREEN}  14. 安装新版 Xray  ${YELLOW}(调用 3x-ui 面板官方脚本)${PLAIN}"
        echo -e "${GREEN}  15. 安装 Sing-box  ${YELLOW}(调用勇哥四合一官方脚本)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${RED}  16. 重启系统       ${YELLOW}(使各项参数彻底生效)${PLAIN}"
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
