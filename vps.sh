#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 终极深度优化脚本 (2026 工业整合版)
#  Logic:    BBR + 深度TCP调优 + 兼容性sysctl写入 + 安全加固
# =========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 1. 权限与基础检查
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：请以 root 运行！${PLAIN}" && exit 1

# 兼容性获取总内存 (MB)
mem_total=$(free -m | awk '/^Mem:/{print $2}') [cite: 30]

echo -e "${BLUE}=== VPS 深度优化脚本 (工业整合版) ===${PLAIN}"

# 2. 核心函数：逐行应用 sysctl (解决容器报错) [cite: 43]
apply_sysctl_settings() {
    local conf_file="$1"
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        local key value
        key=$(echo "$line" | cut -d= -f1 | tr -d ' ')
        value=$(echo "$line" | cut -d= -f2- | tr -d ' ')
        if [[ -n "$key" && -n "$value" ]]; then
            sysctl -w "${key}=${value}" > /dev/null 2>&1 || echo -e "${YELLOW}跳过不支持参数: ${key}${PLAIN}" [cite: 44, 45]
        fi
    done < "$conf_file"
}

# 3. 环境初始化与 Swap
echo -e "${YELLOW}[1/4] 正在初始化基础环境与虚拟内存...${PLAIN}"
if [[ -n "$mem_total" ]] && [[ "$mem_total" -lt 2048 ]] && [[ ! -f /swapfile ]]; then
    echo -e "${BLUE}检测到内存不足 2G，正在创建 2G Swap...${PLAIN}"
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1

# 4. 深度 TCP + BBR 调优整合 [cite: 48, 54]
echo -e "${YELLOW}[2/4] 正在应用深度网络加速 (工业级参数)...${PLAIN}"

cat > /etc/sysctl.d/99-vps-advanced-tune.conf <<EOF
# --- BBR 拥塞控制 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 高并发连接处理 ---
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 20000
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 10000

# --- 深度缓冲区优化 (针对节点业务) [cite: 56] ---
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# --- 链路加速与稳定性 [cite: 57, 58] ---
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1

# --- 连接保活 ---
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# --- 系统限制优化 ---
fs.file-max = 1000000
net.netfilter.nf_conntrack_max = 1000000
EOF

# 使用兼容模式写入
apply_sysctl_settings /etc/sysctl.d/99-vps-advanced-tune.conf [cite: 43]

# 提升文件描述符 [cite: 59]
if ! grep -q "1000000" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf <<EOF
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
fi

# 5. SSH 端口处理 (回车默认不修改)
echo -e "${YELLOW}[3/4] 正在检查 SSH 配置...${PLAIN}"
current_ssh_port=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
current_ssh_port=${current_ssh_port:-22}

echo -e "👉 当前 SSH 端口: ${GREEN}${current_ssh_port}${PLAIN}"
read -p "请输入新端口号 (直接回车保持不变): " new_port

if [[ -z "$new_port" ]] || [[ "$new_port" == "$current_ssh_port" ]]; then
    echo -e "${BLUE}✅ 保持当前配置，跳过 SSH 修改。${PLAIN}"
    final_port=$current_ssh_port
else
    sed -i "s/^#Port .*/Port $new_port/" /etc/ssh/sshd_config
    sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config
    grep -q "^Port $new_port" /etc/ssh/sshd_config || echo "Port $new_port" >> /etc/ssh/sshd_config
    
    # 防火墙自动放行
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$new_port"/tcp > /dev/null 2>&1
    elif command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "$new_port" -j ACCEPT
    fi
    echo -e "${GREEN}✅ SSH 端口计划修改为: $new_port${PLAIN}"
    final_port=$new_port
fi

# 6. 安全防护 (Fail2ban)
echo -e "${YELLOW}[4/4] 正在配置暴力破解防护 (Fail2ban)...${PLAIN}"
if command -v apt >/dev/null 2>&1; then
    apt update -qq && apt install -y fail2ban -qq > /dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    yum install -y fail2ban -q > /dev/null 2>&1
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

# 结束提示
echo -e "${GREEN}======================================${PLAIN}"
echo -e "${BOLD}所有工业级优化已完成！${PLAIN}"
echo -e "🚀 BBR+高级TCP调优：${GREEN}已生效${PLAIN}"
echo -e "📂 文件描述符上限：${GREEN}1,000,000${PLAIN}"
echo -e "🔒 SSH 端口状态：${GREEN}${final_port}${PLAIN}"
echo -e "${GREEN}======================================${PLAIN}"

read -p "是否现在重启系统以应用所有内核参数? (y/n): " confirm_reboot
[[ "$confirm_reboot" =~ ^[Yy]$ ]] && reboot
