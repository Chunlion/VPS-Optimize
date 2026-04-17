#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 全能优化脚本
#  Logic:    常用工具 + Docker(可选) + BBR + TCP深度调优 + 安全
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

echo -e "${BLUE}=== VPS 全能优化脚本 ===${PLAIN}"

# 核心函数：逐行应用 sysctl (解决容器报错)
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
# 一、 常用工具安装与基础初始化
# ---------------------------------------------------------
echo -e "${YELLOW}[1/6] 正在安装常用工具并初始化基础环境...${PLAIN}"

if command -v apt >/dev/null 2>&1; then
    apt update -qq && apt install -y curl wget git nano vim unzip htop net-tools ca-certificates -qq > /dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl wget git nano vim unzip htop net-tools epel-release -q > /dev/null 2>&1
fi

# 内存获取与 Swap
mem_total=$(free -m | awk '/^Mem:/{print $2}')
if [[ -n "$mem_total" ]] && [[ "$mem_total" -lt 2048 ]] && [[ ! -f /swapfile ]]; then
    echo -e "${BLUE}检测到内存不足 2G，正在创建 2G Swap...${PLAIN}"
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1
echo -e "${GREEN}基础环境配置完成！${PLAIN}"

# ---------------------------------------------------------
# 二、 Docker 环境安装 (交互式)
# ---------------------------------------------------------
echo -e "${YELLOW}[2/6] Docker 环境配置${PLAIN}"
read -p "是否安装 Docker 与 Docker-Compose? (回车默认安装, 不安装请输入 n): " docker_choice

if [[ -z "$docker_choice" ]] || [[ "$docker_choice" =~ ^[Yy]$ ]]; then
    if command -v docker >/dev/null 2>&1; then
        echo -e "${BLUE}检测到 Docker 已存在，跳过安装。${PLAIN}"
    else
        echo -e "${BLUE}正在调用官方脚本安装 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker > /dev/null 2>&1
        echo -e "${GREEN}Docker 安装成功！${PLAIN}"
    fi
else
    echo -e "${BLUE}已选择跳过 Docker 安装。${PLAIN}"
fi

# ---------------------------------------------------------
# 三、 深度 TCP + BBR 调优 (核心性能)
# ---------------------------------------------------------
echo -e "${YELLOW}[3/6] 正在应用深度网络加速 (BBR + 工业级参数)...${PLAIN}"

cat > /etc/sysctl.d/99-vps-advanced-tune.conf <<EOF
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

# 深度缓冲区优化 (针对节点业务)
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

# 连接保活
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# 系统限制
fs.file-max = 1000000
EOF

apply_sysctl_settings /etc/sysctl.d/99-vps-advanced-tune.conf

if ! grep -q "1000000" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf <<EOF
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
fi

# ---------------------------------------------------------
# 四、 SSH 端口处理 (回车默认不修改)
# ---------------------------------------------------------
echo -e "${YELLOW}[4/6] 正在检查 SSH 配置...${PLAIN}"
current_ssh_port=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
current_ssh_port=${current_ssh_port:-22}

echo -e "👉 当前 SSH 端口: ${GREEN}${current_ssh_port}${PLAIN}"
read -p "请输入新端口号 (直接回车保持不变): " new_port

if [[ -z "$new_port" ]] || [[ "$new_port" == "$current_ssh_port" ]]; then
    echo -e "${BLUE}✅ 保持当前配置。${PLAIN}"
    final_port=$current_ssh_port
else
    sed -i "s/^#Port .*/Port $new_port/" /etc/ssh/sshd_config
    sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config
    grep -q "^Port $new_port" /etc/ssh/sshd_config || echo "Port $new_port" >> /etc/ssh/sshd_config
    
    if command -v ufw >/dev/null 2>&1; then ufw allow "$new_port"/tcp > /dev/null 2>&1
    elif command -v iptables >/dev/null 2>&1; then iptables -I INPUT -p tcp --dport "$new_port" -j ACCEPT; fi
    echo -e "${GREEN}✅ 端口已计划修改为: $new_port${PLAIN}"
    final_port=$new_port
fi

# ---------------------------------------------------------
# 五、 安全防护 (Fail2ban)
# ---------------------------------------------------------
echo -e "${YELLOW}[5/6] 正在配置暴力破解防护 (Fail2ban)...${PLAIN}"
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
# 六、 签名与结束
# ---------------------------------------------------------
echo -e "${GREEN}===============================================${PLAIN}"
echo -e "   ${BOLD}🚀 VPS 深度优化任务已完成！${PLAIN}"
echo -e "${GREEN}===============================================${PLAIN}"
echo -e "  ${CYAN}🏠 项目主页:${PLAIN}  https://github.com/Chunlion/VPS-Optimize"
echo -e "  ${CYAN}🌟 觉得好用?${PLAIN}  请给 GitHub 仓库点个 Star ！"
echo -e "${GREEN}===============================================${PLAIN}"

read -p "是否现在重启系统以应用所有配置? (y/n): " confirm_reboot
[[ "$confirm_reboot" =~ ^[Yy]$ ]] && reboot
