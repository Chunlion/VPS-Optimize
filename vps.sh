#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 终极全能控制面板 (完美排版修复版)
#  Features: 极致排版/智能防火墙/全能工具/BBR/测试合集/热更新
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

# 权限检查
[[ $EUID -ne 0 ]] && echo -e "${RED}❌ 错误：请以 root 运行！${PLAIN}" && exit 1

# 系统识别
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

UPDATE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh"

# 快捷指令注册
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
# 1. 基础环境初始化
# ---------------------------------------------------------
func_base_init() {
    clear
    echo -e "${CYAN}👉 正在安装基础工具、限制日志并开启基础 BBR...${PLAIN}"
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
    echo -e "${GREEN}✅ 基础初始化完成，BBR已激活！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 2. 系统高级开关 (y/n 模式 + 智能防火墙)
# ---------------------------------------------------------
func_system_tweaks() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}⚙️  系统高级开关 (输入 y 开启, n 关闭)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
        [ "$ipv6_status" == "0" ] && str_ipv6="${GREEN}开启中${PLAIN}" || str_ipv6="${RED}已禁用${PLAIN}"
        ping_status=$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null)
        [ "$ping_status" == "0" ] && str_ping="${GREEN}允许被Ping${PLAIN}" || str_ping="${RED}禁Ping中${PLAIN}"
        if [[ "$OS" =~ debian|ubuntu ]]; then
            update_status=$(systemctl is-active unattended-upgrades 2>/dev/null)
            fw_status=$(ufw status 2>/dev/null | grep -wi active)
        else
            update_status=$(systemctl is-active dnf-automatic.timer 2>/dev/null)
            fw_status=$(systemctl is-active firewalld 2>/dev/null)
        fi
        [ "$update_status" == "active" ] && str_update="${GREEN}开启中${PLAIN}" || str_update="${RED}已禁用${PLAIN}"
        [ "$fw_status" == "active" ] || [ -n "$fw_status" ] && str_fw="${GREEN}开启中${PLAIN}" || str_fw="${RED}已禁用${PLAIN}"

        echo -e "${GREEN}  1. IPv6 网络${PLAIN}      当前状态: [ $str_ipv6 ]"
        echo -e "${GREEN}  2. 被人Ping状态${PLAIN}   当前状态: [ $str_ping ]"
        echo -e "${GREEN}  3. 自动更新服务${PLAIN}   当前状态: [ $str_update ]"
        echo -e "${GREEN}  4. 系统安全防火墙${PLAIN} 当前状态: [ $str_fw ]"
        echo -e "${GREEN}  5. 彻底清理系统垃圾${PLAIN} (日志/缓存/无用包)"
        echo -e "${GREEN}  6. 查看防火墙规则${PLAIN}   (放行规则列表)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择操作: " tweak_choice

        case $tweak_choice in
            1) read -p "❓ 是否开启 IPv6？(y/n): " yn; if [[ "$yn" =~ ^[Yy]$ ]]; then rm -f /etc/sysctl.d/99-disable-ipv6.conf; sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null; echo -e "${GREEN}✅ 已开启${PLAIN}"; else echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf; sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null; echo -e "${RED}✅ 已禁用${PLAIN}"; fi; sleep 1 ;;
            2) read -p "❓ 是否允许被 Ping？(y/n): " yn; if [[ "$yn" =~ ^[Yy]$ ]]; then rm -f /etc/sysctl.d/99-disable-ping.conf; sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null; echo -e "${GREEN}✅ 已允许${PLAIN}"; else echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf; sysctl -p /etc/sysctl.d/99-disable-ping.conf >/dev/null; echo -e "${RED}✅ 已禁Ping${PLAIN}"; fi; sleep 1 ;;
            3) read -p "❓ 是否开启自动更新？(y/n): " yn; if [[ "$yn" =~ ^[Yy]$ ]]; then if [[ "$OS" =~ debian|ubuntu ]]; then apt install -y unattended-upgrades -qq >/dev/null; systemctl enable --now unattended-upgrades >/dev/null; else yum install -y dnf-automatic -q >/dev/null; systemctl enable --now dnf-automatic.timer >/dev/null; fi; echo -e "${GREEN}✅ 已开启${PLAIN}"; else if [[ "$OS" =~ debian|ubuntu ]]; then systemctl disable --now unattended-upgrades >/dev/null; else systemctl disable --now dnf-automatic.timer >/dev/null; fi; echo -e "${RED}✅ 已禁用${PLAIN}"; fi; sleep 1 ;;
            4) read -p "❓ 是否开启防火墙并自动放行活动端口？(y/n): " yn; if [[ "$yn" =~ ^[Yy]$ ]]; then active_ports=$(ss -tuln | grep -E 'LISTEN|UNCONN' | grep -v '127.0.0.1' | awk '{print $5}' | rev | cut -d: -f1 | rev | sort -nu | grep -E '^[0-9]+$'); if [[ "$OS" =~ debian|ubuntu ]]; then apt install ufw -y >/dev/null; ufw default deny incoming >/dev/null; ufw default allow outgoing >/dev/null; for p in $active_ports; do ufw allow $p >/dev/null; done; ufw --force enable >/dev/null; else yum install firewalld -y >/dev/null; systemctl enable --now firewalld >/dev/null; for p in $active_ports; do firewall-cmd --permanent --add-port=${p}/tcp >/dev/null; firewall-cmd --permanent --add-port=${p}/udp >/dev/null; done; firewall-cmd --reload >/dev/null; fi; echo -e "${GREEN}✅ 防火墙已开启并放行端口: $active_ports${PLAIN}"; else if [[ "$OS" =~ debian|ubuntu ]]; then ufw disable >/dev/null; else systemctl disable --now firewalld >/dev/null; fi; echo -e "${RED}✅ 防火墙已关闭${PLAIN}"; fi; read -n 1 -s -r -p "按任意键继续..." ;;
            6) if [[ "$OS" =~ debian|ubuntu ]]; then ufw status verbose; else firewall-cmd --list-all; fi; read -n 1 -s -r -p "按任意键继续..." ;;
            5) echo -e "${CYAN}👉 正在清理系统垃圾...${PLAIN}"; if [[ "$OS" =~ debian|ubuntu ]]; then apt autoremove --purge -y; apt clean; else yum autoremove -y; yum clean all; fi; journalctl --vacuum-time=1d > /dev/null 2>&1; echo -e "${GREEN}✅ 清理完成！${PLAIN}"; sleep 1 ;;
            0) break ;;
        esac
    done
}

# ---------------------------------------------------------
# 3. 常用环境及软件
# ---------------------------------------------------------
func_env_install() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📦 常用环境及软件一键安装库${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. Docker 引擎   ${YELLOW}  2. Python 环境   ${GREEN}  3. iperf3 工具${PLAIN}"
        echo -e "${GREEN}  4. Realm 转发    ${YELLOW}  5. Gost 隧道     ${GREEN}  6. 极光面板${PLAIN}"
        echo -e "${GREEN}  7. 哪吒监控      ${YELLOW}  8. WARP (CF)     ${GREEN}  9. Aria2 下载${PLAIN}"
        echo -e "${GREEN} 10. 宝塔面板      ${YELLOW} 11. PVE 虚拟化    ${GREEN} 12. Argox 节点${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${CYAN}
