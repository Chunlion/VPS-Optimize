#!usrbinenv bash

# =========================================================
#  Project  VPS 终极一键优化脚本 (2026 深度定制版)
#  Logic    BBR + TCP深度调优 + SSH按需加固
#  Ref      基于工业级 TCP 调优参数优化
# =========================================================

RED='033[0;31m'
GREEN='033[0;32m'
YELLOW='033[0;33m'
BLUE='033[0;34m'
PLAIN='033[0m'

[[ $EUID -ne 0 ]] && echo -e ${RED}错误：请以 root 运行！${PLAIN} && exit 1

echo -e ${BLUE}=== VPS 深度优化脚本 (回车跳过端口修改) ===${PLAIN}

# ---------------------------------------------------------
# 一、 环境初始化与 Swap 检查
# ---------------------------------------------------------
echo -e ${YELLOW}[14] 正在初始化基础环境...${PLAIN}
# 自动创建 2G Swap (小内存 VPS 救命用)
mem_total=$(free -m  grep Mem  awk '{print $2}')
if [ $mem_total -lt 2048 ] && [ ! -f swapfile ]; then
    echo -e ${BLUE}检测到内存小于 2G，正在创建 Swap 虚拟内存...${PLAIN}
    fallocate -l 2G swapfile && chmod 600 swapfile && mkswap swapfile && swapon swapfile
    echo 'swapfile none swap sw 0 0'  etcfstab
fi

# ---------------------------------------------------------
# 二、 BBR 与 TCP 深度调优 (基于你提供的参数)
# ---------------------------------------------------------
echo -e ${YELLOW}[24] 正在应用深度网络加速 (BBR + TCP Tune)...${PLAIN}

# 写入内核参数 [cite 47, 53]
cat  etcsysctl.d99-vps-deep-optimize.conf EOF
# BBR 拥塞控制 [cite 48]
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP 缓冲区优化 (针对高延迟节点) 
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

# 连接复用与保活 [cite 54, 55]
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# 链路特性增强 [cite 57, 58]
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
fs.file-max = 1000000
EOF

sysctl --system  devnull 2&1

# 提升文件句柄限制 [cite 59]
if ! grep -q 1000000 etcsecuritylimits.conf; then
    cat  etcsecuritylimits.conf EOF
 soft nofile 1000000
 hard nofile 1000000
EOF
fi

# ---------------------------------------------------------
# 三、 SSH 端口处理 (核心逻辑：回车默认不修改)
# ---------------------------------------------------------
echo -e ${YELLOW}[34] 正在检查 SSH 配置...${PLAIN}
current_ssh_port=$(grep ^Port etcsshsshd_config  awk '{print $2}')
[ -z $current_ssh_port ] && current_ssh_port=22

echo -e 👉 当前 SSH 端口为 ${GREEN}$current_ssh_port${PLAIN}
read -p 请输入新端口号 (直接回车保持不变)  new_port

if [ -z $new_port ]  [ $new_port == $current_ssh_port ]; then
    echo -e ${BLUE}✅ 保持当前配置，跳过 SSH 修改。${PLAIN}
    final_port=$current_ssh_port
else
    # 修改端口逻辑
    sed -i s^#Port .Port $new_port etcsshsshd_config
    sed -i s^Port .Port $new_port etcsshsshd_config
    if ! grep -q ^Port etcsshsshd_config; then echo Port $new_port  etcsshsshd_config; fi
    
    # 防火墙兼容处理
    if command -v ufw devnull 2&1; then
        ufw allow $new_porttcp  devnull 2&1
    elif command -v firewall-cmd devnull 2&1; then
        firewall-cmd --permanent --add-port=$new_porttcp  devnull 2&1
        firewall-cmd --reload  devnull 2&1
    fi
    echo -e ${GREEN}✅ SSH 端口已计划修改为 $new_port (重启后生效)${PLAIN}
    final_port=$new_port
fi

# ---------------------------------------------------------
# 四、 系统加固 (Fail2ban)
# ---------------------------------------------------------
echo -e ${YELLOW}[44] 正在配置 Fail2ban 暴力破解防护...${PLAIN}
if command -v apt devnull 2&1; then
    apt install -y fail2ban  devnull 2&1
elif command -v yum devnull 2&1; then
    yum install -y fail2ban  devnull 2&1
fi

cat EOF  etcfail2banjail.local
[sshd]
enabled = true
port    = $final_port
findtime = 10m
maxretry = 5
bantime = 24h
EOF
systemctl restart fail2ban  devnull 2&1

# ---------------------------------------------------------
# 结束提示
# ---------------------------------------------------------
echo -e ${GREEN}======================================${PLAIN}
echo -e ${BOLD}所有优化任务已完成！${PLAIN}
echo -e 🚀 BBRTCP 深度调优：${GREEN}已应用${PLAIN}
echo -e 🔒 SSH 端口状态：${GREEN}$final_port${PLAIN}
echo -e ${YELLOW}提示：建议重启系统以使内核参数完美生效。${PLAIN}
echo -e ${GREEN}======================================${PLAIN}

read -p 是否现在重启 (yn)  confirm_reboot
[[ $confirm_reboot == y  $confirm_reboot == Y ]] && reboot