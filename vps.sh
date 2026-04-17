#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 全能优化脚本
#  Logic:    常用工具 + Docker + BBR + TCP深度调优 + 安全
#  Author:   Chunlion
# =========================================================


# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'
BOLD='\033[1m'

# 1. 基础检查
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：请以 root 运行！${PLAIN}" && exit 1

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

echo -e "${BLUE}=== VPS 优化脚本 ===${PLAIN}"

# 核心函数：逐行应用 sysctl 
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
# 一、 常用工具与系统自动更新 (交互式)
# ---------------------------------------------------------
echo -e "${YELLOW}[1/7] 基础工具与自动更新配置${PLAIN}"

# 安装基础工具
if [[ "$OS" =~ debian|ubuntu ]]; then
    apt update -qq && apt install -y curl wget git nano unzip htop -qq > /dev/null 2>&1
elif [[ "$OS" =~ centos|rhel|rocky|almalinux ]]; then
    yum install -y curl wget git nano unzip htop epel-release -q > /dev/null 2>&1
fi

read -p "是否开启系统自动安全更新? (回车默认开启, 禁用请输入 n): " update_choice
if [[ -z "$update_choice" ]] || [[ "$update_choice" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}正在配置自动安全更新...${PLAIN}"
    if [[ "$OS" =~ debian|ubuntu ]]; then
        apt install -y unattended-upgrades -qq > /dev/null 2>&1
        echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
        dpkg-reconfigure -f noninteractive unattended-upgrades > /dev/null 2>&1
    elif [[ "$OS" =~ centos|rhel|rocky|almalinux ]]; then
        yum install -y dnf-automatic -q > /dev/null 2>&1
        systemctl enable --now dnf-automatic.timer > /dev/null 2>&1
    fi
    echo -e "${GREEN}自动安全更新已开启！${PLAIN}"
else
    echo -e "${BLUE}已跳过自动更新配置。${PLAIN}"
fi

# ---------------------------------------------------------
# 二、 系统日志 (Journald) 优化
# ---------------------------------------------------------
echo -e "${YELLOW}[2/7] 正在限制系统日志上限为 100M...${PLAIN}"
mkdir -p /etc/systemd/journald.conf.d/
cat > /etc/systemd/journald.conf.d/99-limit.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF
systemctl restart systemd-journald > /dev/null 2>&1
echo -e "${GREEN}日志上限已设为 100M。${PLAIN}"

# ---------------------------------------------------------
# 三、 虚拟内存 (Swap) 与 优先级调优
# ---------------------------------------------------------
echo -e "${YELLOW}[3/7] 正在优化虚拟内存优先级 (Swappiness)...${PLAIN}"
mem_total=$(free -m | awk '/^Mem:/{print $2}')
if [[ -n "$mem_total" ]] && [[ "$mem_total" -lt 2048 ]] && [[ ! -f /swapfile ]]; then
    echo -e "${BLUE}检测到内存不足 2G，正在创建 2G Swap...${PLAIN}"
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
# 性能优化：vm.swappiness=10
echo "vm.swappiness = 10" > /etc/sysctl.d/99-swappiness.conf
sysctl -p /etc/sysctl.d/99-swappiness.conf > /dev/null 2>&1
timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1

# ---------------------------------------------------------
# 四、 Docker 环境安装 (交互式)
# ---------------------------------------------------------
echo -e "${YELLOW}[4/7] Docker 环境配置${PLAIN}"
read -p "是否安装 Docker 与 Docker-Compose? (回车默认安装, 不安装请输入 n): " docker_choice

if [[ -z "$docker_choice" ]] || [[ "$docker_choice" =~ ^[Yy]$ ]]; then
    if command -v docker >/dev/null 2>&1; then
        echo -e "${BLUE}检测到 Docker 已存在，跳过安装。${PLAIN}"
    else
        echo -e "${BLUE}正在安装 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker > /dev/null 2>&1
    fi
else
    echo -e "${BLUE}已跳过 Docker 安装。${PLAIN}"
fi

# ---------------------------------------------------------
# 五、 深度 TCP + BBR 调优 (核心性能 )
# ---------------------------------------------------------
echo -e "${YELLOW}[5/7] 正在应用 BBR + 32MB 深度缓冲区调优...${PLAIN}"

cat > /etc/sysctl.d/99-vps-industrial-tune.conf <<EOF
# BBR 拥塞控制 
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 高并发与连接复用 
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 20000
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 10000

# 深度缓冲区优化 
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

# 链路特性增强 
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1

# 系统限制优化 
fs.file-max = 1000000
EOF

apply_sysctl_settings /etc/sysctl.d/99-vps-industrial-tune.conf

if ! grep -q "1000000" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf <<EOF
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
fi

# ---------------------------------------------------------
# 六、 SSH 端口与 Fail2ban
# ---------------------------------------------------------
echo -e "${YELLOW}[6/7] 正在配置 SSH 与 暴力破解防护...${PLAIN}"
current_ssh_port=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
current_ssh_port=${current_ssh_port:-22}
read -p "请输入新 SSH 端口 (直接回车保持 $current_ssh_port): " new_port
final_port=${new_port:-$current_ssh_port}

if [[ "$final_port" != "$current_ssh_port" ]]; then
    sed -i "s/^#Port .*/Port $final_port/" /etc/ssh/sshd_config
    sed -i "s/^Port .*/Port $final_port/" /etc/ssh/sshd_config
    grep -q "^Port $final_port" /etc/ssh/sshd_config || echo "Port $final_port" >> /etc/ssh/sshd_config
    if command -v ufw >/dev/null 2>&1; then ufw allow "$final_port"/tcp >/dev/null;
    elif command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --permanent --add-port="$final_port"/tcp >/dev/null; firewall-cmd --reload >/dev/null; fi
fi

cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port    = $final_port
findtime = 10m
maxretry = 5
bantime = 24h
EOF
systemctl restart fail2ban > /dev/null 2>&1

# ---------------------------------------------------------
# 七、 签名与结束
# ---------------------------------------------------------
echo -e "${GREEN}===============================================${PLAIN}"
echo -e "   ${BOLD}🚀 VPS 深度优化已完成！${PLAIN}"
echo -e "${GREEN}===============================================${PLAIN}"
echo -e "  ${CYAN}🏠 项目主页:${PLAIN}  https://github.com/Chunlion/VPS-Optimize"
echo -e "  ${CYAN}🌟 觉得好用?${PLAIN}  请给 GitHub 仓库点个 Star ！"
echo -e "${GREEN}===============================================${PLAIN}"

read -p "是否现在重启系统以彻底生效? (y/n): " confirm_reboot
[[ "$confirm_reboot" =~ ^[Yy]$ ]] && reboot
