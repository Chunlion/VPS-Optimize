#!/usr/bin/env bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 权限检查
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：请以 root 运行！${PLAIN}" && exit 1

echo -e "${BLUE}=== VPS 深度优化脚本 (回车跳过端口修改) ===${PLAIN}"

# ---------------------------------------------------------
# 一、 环境初始化与 Swap 检查
# ---------------------------------------------------------
echo -e "${YELLOW}[1/4] 正在初始化基础环境...${PLAIN}"

# 健壮地获取总内存 (MB)
mem_total=$(free -m | awk '/^Mem:/{print $2}')

# 增加对变量是否为空的检查，防止语法报错
if [[ -n "$mem_total" ]] && [[ "$mem_total" -lt 2048 ]] && [[ ! -f /swapfile ]]; then
    echo -e "${BLUE}检测到内存小于 2G，正在创建 Swap 虚拟内存...${PLAIN}"
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

# ---------------------------------------------------------
# 二、 BBR 与 TCP 深度调优
# ---------------------------------------------------------
echo -e "${YELLOW}[2/4] 正在应用深度网络加速 (BBR + TCP Tune)...${PLAIN}"

cat > /etc/sysctl.d/99-vps-deep-optimize.conf <<EOF
# BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP 缓冲区优化
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

# 连接复用与保活
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# 链路特性增强
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
fs.file-max = 1000000
EOF

sysctl --system > /dev/null 2>&1

# 提升文件句柄限制
if ! grep -q "1000000" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf <<EOF
* soft nofile 1000000
* hard nofile 1000000
EOF
fi

# ---------------------------------------------------------
# 三、 SSH 端口处理 (回车默认不修改)
# ---------------------------------------------------------
echo -e "${YELLOW}[3/4] 正在检查 SSH 配置...${PLAIN}"
# 兼容处理：提取端口号并确保它是数字
current_ssh_port=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}')
current_ssh_port=${current_ssh_port:-22}

echo -e "👉 当前 SSH 端口为: ${GREEN}${current_ssh_port}${PLAIN}"
read -p "请输入新端口号 (直接回车保持不变): " new_port

# 如果输入为空或与当前相同，则跳过
if [[ -z "$new_port" ]] || [[ "$new_port" == "$current_ssh_port" ]]; then
    echo -e "${BLUE}✅ 保持当前配置，跳过 SSH 修改。${PLAIN}"
    final_port=$current_ssh_port
else
    # 修改端口
    sed -i "s/^#Port .*/Port $new_port/" /etc/ssh/sshd_config
    sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config
    if ! grep -q "^Port" /etc/ssh/sshd_config; then echo "Port $new_port" >> /etc/ssh/sshd_config; fi
    
    # 自动尝试开放防火墙 (UFW/Iptables)
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$new_port"/tcp > /dev/null 2>&1
    elif command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "$new_port" -j ACCEPT
    fi
    echo -e "${GREEN}✅ SSH 端口已计划修改为: $new_port${PLAIN}"
    final_port=$new_port
fi

# ---------------------------------------------------------
# 四、 系统加固 (Fail2ban)
# ---------------------------------------------------------
echo -e "${YELLOW}[4/4] 正在配置 Fail2ban 暴力破解防护...${PLAIN}"
# 简单检测包管理器并安装
if command -v apt >/dev/null 2>&1; then
    apt update && apt install -y fail2ban > /dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    yum install -y fail2ban > /dev/null 2>&1
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
# 结束提示
# ---------------------------------------------------------
echo -e "${GREEN}======================================${PLAIN}"
echo -e "${BOLD}所有优化任务已完成！${PLAIN}"
echo -e "🚀 BBR/TCP 深度调优：已应用"
echo -e "🔒 SSH 端口状态：${final_port}"
echo -e "${GREEN}======================================${PLAIN}"

read -p "是否现在重启系统以应用所有参数? (y/n): " confirm_reboot
[[ "$confirm_reboot" =~ ^[Yy]$ ]] && reboot
