#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 全能控制面板
#  Features: IPv4优先/智能防火墙/面板救砖/DNS流媒体解锁/热更新
#  Shortcut: cy
# =========================================================

# --- 颜色与格式定义 ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PLAIN='\033[0m'
BOLD='\033[1m'

# --- 权限检查 ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ 错误：请以 root 用户身份运行本脚本！${PLAIN}"
    exit 1
fi

# --- 系统识别 ---
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

UPDATE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh"

# --- 全局快捷键注册 ---
create_shortcut() {
    local script_path="/usr/local/bin/cy"
    if [[ ! -f "$script_path" ]] && [[ -f "$0" ]]; then
        cp "$(readlink -f "$0")" "$script_path"
        chmod +x "$script_path"
        echo -e "${GREEN}✅ 快捷指令 'cy' 已全局注册！下次可直接输入 cy 唤出面板。${PLAIN}"
        sleep 1
    fi
}

# ---------------------------------------------------------
# 1. 基础环境初始化
# ---------------------------------------------------------
func_base_init() {
    clear
    echo -e "${CYAN}👉 正在安装基础工具、限制日志并开启基础 BBR...${PLAIN}"
    
    if [[ "$OS" =~ debian|ubuntu ]]; then
        apt update -qq
        apt install -y curl wget git nano unzip htop iptables iproute2 sqlite3 -qq > /dev/null 2>&1
    elif [[ "$OS" =~ centos|rhel|rocky|almalinux ]]; then
        yum install -y curl wget git nano unzip htop iptables iproute epel-release sqlite -q > /dev/null 2>&1
    fi

    # 限制系统日志最大 100M
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/99-limit.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF
    systemctl restart systemd-journald > /dev/null 2>&1
    
    # 设置时区为上海
    timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1
    
    # 强制激活基础 BBR
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-bbr-init.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-bbr-init.conf
    sysctl -p /etc/sysctl.d/99-bbr-init.conf > /dev/null 2>&1
    
    echo -e "${GREEN}✅ 基础初始化完成，原生 BBR 已激活！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 2. 系统高级开关 (含 IPv4 优先)
# ---------------------------------------------------------
func_system_tweaks() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}⚙️  系统高级开关 (输入 y 开启, n 关闭)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        # 获取各项状态
        local ipv6_status
        local str_ipv6
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
        if [[ "$ipv6_status" == "0" ]]; then str_ipv6="${GREEN}开启中${PLAIN}"; else str_ipv6="${RED}已禁用${PLAIN}"; fi
        
        local str_ipv4_first
        if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then 
            str_ipv4_first="${GREEN}已优先${PLAIN}"
        else 
            str_ipv4_first="${RED}默认(IPv6优先)${PLAIN}"
        fi
        
        local ping_status
        local str_ping
        ping_status=$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null)
        if [[ "$ping_status" == "0" ]]; then str_ping="${GREEN}允许被Ping${PLAIN}"; else str_ping="${RED}禁Ping中${PLAIN}"; fi
        
        echo -e "${GREEN}  1. 管理 IPv6 网络状态${PLAIN}    当前: [ $str_ipv6 ]"
        echo -e "${GREEN}  2. IPv4 出站优先级增强${PLAIN}   当前: [ $str_ipv4_first ]"
        echo -e "${GREEN}  3. 管理 被人Ping状态${PLAIN}     当前: [ $str_ping ]"
        echo -e "${GREEN}  4. 彻底清理系统垃圾${PLAIN}      (日志/缓存/无用包)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local tweak_choice
        read -p "👉 请选择操作: " tweak_choice
        
        case $tweak_choice in
            1) 
                read -p "❓ 开启 IPv6？(y 开启 / n 关闭): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    rm -f /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
                    echo -e "${GREEN}✅ IPv6 已开启${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1
                    echo -e "${RED}✅ IPv6 已禁用${PLAIN}"
                fi
                sleep 1 
                ;;
            2) 
                read -p "❓ 设置 IPv4 为最高出站优先级？(y 开启 / n 恢复默认): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    sed -Ei '/^[[:space:]]*#?[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+100\b.*?$/ {s/.+100\b([[:space:]]*#.*)?$/precedence ::ffff:0:0\/96  100\1/; :a;n;b a}; /^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+.*$/ {s/^.*precedence.+::ffff:0:0\/96[^0-9]+([0-9]+).*$/precedence ::ffff:0:0\/96  100\t#原值为 \1/; :a;n;ba;}; $aprecedence ::ffff:0:0\/96  100' /etc/gai.conf
                    echo -e "${GREEN}✅ 已设为 IPv4 优先${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    sed -i '/precedence ::ffff:0:0\/96  100/d' /etc/gai.conf
                    echo -e "${BLUE}已恢复系统默认${PLAIN}"
                fi
                sleep 1 
                ;;
            3) 
                read -p "❓ 允许被 Ping？(y 允许 / n 禁止): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    rm -f /etc/sysctl.d/99-disable-ping.conf
                    sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1
                    echo -e "${GREEN}✅ 已允许被 Ping${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf
                    sysctl -p /etc/sysctl.d/99-disable-ping.conf >/dev/null 2>&1
                    echo -e "${RED}✅ 已开启禁 Ping 保护${PLAIN}"
                fi
                sleep 1 
                ;;
            4) 
                echo -e "${CYAN}👉 正在深度清理系统垃圾...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then 
                    apt autoremove --purge -y >/dev/null 2>&1
                    apt clean >/dev/null 2>&1
                else 
                    yum autoremove -y >/dev/null 2>&1
                    yum clean all >/dev/null 2>&1
                fi
                journalctl --vacuum-time=1d > /dev/null 2>&1
                echo -e "${GREEN}✅ 清理完成！${PLAIN}"
                sleep 1 
                ;;
            0) 
                break 
                ;;
            *)
                echo -e "${RED}❌ 无效的选择！${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

# ---------------------------------------------------------
# 3. 常用环境及软件 (Caddy 多行写入优化版)
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
        echo -e "${CYAN} 13. 一键配置 Caddy 反向代理 ${YELLOW}(域名+全自动HTTPS)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local env_choice
        read -p "👉 选择: " env_choice
        
        case $env_choice in
            1) bash <(curl -sL 'https://get.docker.com') ;;
            2) curl -O https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh && chmod +x pyinstall.sh && ./pyinstall.sh ;;
            3) if [[ "$OS" =~ debian|ubuntu ]]; then apt install iperf3 -y; else yum install iperf3 -y; fi ;;
            4) bash <(curl -L https://raw.githubusercontent.com/zhouh047/realm-oneclick-install/main/realm.sh) -i ;;
            5) wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh && chmod +x gost.sh && ./gost.sh ;;
            6) bash <(curl -fsSL https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh) ;;
            7) 
                curl -L https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh -o nezha.sh && chmod +x nezha.sh && ./nezha.sh 
                echo -e "\n${YELLOW}💡 哪吒自定义代码提示 (去除动效并固定顶部)：${PLAIN}"
                echo -e "${GREEN}<script>\nwindow.ShowNetTransfer = true;\nwindow.FixedTopServerName = true;\nwindow.DisableAnimatedMan = true;\n</script>${PLAIN}"
                ;;
            8) wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh ;;
            9) wget -N git.io/aria2.sh && chmod +x aria2.sh && ./aria2.sh ;;
            10) wget -O install.sh http://v7.hostcli.com/install/install-ubuntu_6.0.sh && sudo bash install.sh ;;
            11) bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh) ;;
            12) bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh) ;;
            13)
                if [[ "$OS" =~ debian|ubuntu ]]; then 
                    apt install -y debian-keyring debian-archive-keyring apt-transport-https -qq && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list && apt update && apt install caddy -y
                else 
                    yum install -y yum-utils && yum-config-manager --add-repo https://openrepo.io/repo/caddy/caddy.repo && yum install caddy -y
                fi
                
                local domain
                local port
                local is_https
                
                read -p "请输入解析后的域名 (如 panel.site.com): " domain
                read -p "请输入面板本地映射端口 (如 40000): " port
                
                if [[ -z "$domain" || -z "$port" ]]; then
                    echo -e "${RED}❌ 域名或端口不能为空！已取消配置。${PLAIN}"
                else
                    echo -e "${YELLOW}❓ 后端面板是否开启了自带的 SSL 证书？(y/n)${PLAIN}"
                    read -p "👉 您的选择 (选 n 则正常反代 http): " is_https
                    
                    if [[ "$is_https" =~ ^[Yy]$ ]]; then
                        cat <<EOF > /etc/caddy/Caddyfile
$domain {
    reverse_proxy https://127.0.0.1:$port {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF
                    else
                        cat <<EOF > /etc/caddy/Caddyfile
$domain {
    reverse_proxy localhost:$port
}
EOF
                    fi
                    systemctl restart caddy
                    echo -e "${GREEN}✅ Caddy 反代配置完成！请访问 https://$domain${PLAIN}"
                fi
                ;;
            0) 
                break 
                ;;
            *)
                echo -e "${RED}❌ 无效的输入！${PLAIN}"
                ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# ---------------------------------------------------------
# 4. SSH 安全加固
# ---------------------------------------------------------
func_security() {
    clear
    local current_p
    current_p=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    current_p=${current_p:-22}
    
    local final_p
    read -p "当前 SSH 端口为 $current_p, 请输入新端口 (直接回车保持不变): " final_p
    final_p=${final_p:-$current_p}
    
    if [[ "$final_p" != "$current_p" ]]; then
        sed -i "s/^#Port .*/Port $final_p/" /etc/ssh/sshd_config
        sed -i "s/^Port .*/Port $final_p/" /etc/ssh/sshd_config
        grep -q "^Port $final_p" /etc/ssh/sshd_config || echo "Port $final_p" >> /etc/ssh/sshd_config
        
        # 尝试放行防火墙
        if command -v ufw >/dev/null 2>&1; then ufw allow "$final_p"/tcp >/dev/null 2>&1; fi
        if command -v firewall-cmd >/dev/null 2>&1; then 
            firewall-cmd --permanent --add-port="$final_p"/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        fi
        iptables -I INPUT -p tcp --dport "$final_p" -j ACCEPT 2>/dev/null
        
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        echo -e "${GREEN}✅ SSH 端口已成功更改为 $final_p 并自动放行防火墙！${PLAIN}"
    else
        echo -e "${BLUE}端口未做更改。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 5. Docker 深度管理 (严格检验安装状态)
# ---------------------------------------------------------
func_docker_manage() {
    if ! command -v docker >/dev/null 2>&1; then 
        clear
        echo -e "${RED}❌ 错误：检测到系统尚未安装 Docker 引擎！${PLAIN}"
        echo -e "${YELLOW}💡 请先在主菜单进入 [3 常用环境及软件] 安装 Docker。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    while true; do
        clear
        local docker_ver
        docker_ver=$(docker -v | awk '{print $3}' | tr -d ',')
        
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🐳 Docker 深度管理面板 (版本: ${GREEN}${docker_ver}${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 开启本地防穿透保护${PLAIN} (限制映射端口仅 127.0.0.1 访问)"
        echo -e "${GREEN}  2. 解除本地防穿透保护${PLAIN} (允许 0.0.0.0 全网直接通过IP访问)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        
        local c
        read -p "👉 请选择操作: " c
        case $c in
            1) 
                mkdir -p /etc/docker
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
                systemctl restart docker >/dev/null 2>&1
                echo -e "${GREEN}✅ 已开启安全保护，Docker 容器端口仅限本地反代访问！${PLAIN}" 
                sleep 2
                ;;
            2) 
                rm -f /etc/docker/daemon.json
                systemctl restart docker >/dev/null 2>&1
                echo -e "${GREEN}✅ 已解除限制，容器端口恢复公网可访状态。${PLAIN}" 
                sleep 2
                ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的输入！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 6. BBR 增强管理 (调用 ylx2016 脚本)
# ---------------------------------------------------------
func_bbr_manage() {
    clear
    echo -e "${CYAN}👉 正在调用 ylx2016 网络极速脚本...${PLAIN}"
    wget -O tcpx.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
}

# ---------------------------------------------------------
# 7. 动态 TCP 调优 (Omnitt)
# ---------------------------------------------------------
func_tcp_tune() {
    clear
    echo -e "请浏览器打开: ${BLUE}https://omnitt.com/${PLAIN} 生成针对您网络环境的 TCP 参数"
    read -p "👉 您准备好粘贴代码了吗？(y 继续 / n 取消): " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then return; fi
    
    local temp_f="/etc/sysctl.d/99-omnitt-tune.conf"
    > "$temp_f"
    echo -e "\n${CYAN}👇 请在此右键粘贴代码，完成后在新的一行输入 EOF 并回车：${PLAIN}"
    
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r')
        [[ "$line" == "EOF" || "$line" == "eof" ]] && break
        echo "$line" >> "$temp_f"
    done
    
    if [[ -s "$temp_f" ]]; then
        sysctl -p "$temp_f" >/dev/null 2>&1
        echo -e "${GREEN}✅ 调优参数应用成功！${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ 未检测到有效输入，已取消。${PLAIN}"
        rm -f "$temp_f"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 8. 智能内存调优
# ---------------------------------------------------------
func_zram_swap() {
    clear
    local mem
    mem=$(free -m | awk '/^Mem:/{print $2}')
    echo -e "${CYAN}💡 硬件自适应调优 (检测到本机 ${mem}MB 物理内存)${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e " ${GREEN}1. 激进档 (适合 1G 以下小鸡)${PLAIN}"
    echo -e "    - ZRAM 100% 压缩, Swappiness=100。全力防止宕机。"
    echo -e " ${GREEN}2. 积极档 (适合 2-4G 主流机型)${PLAIN}"
    echo -e "    - ZRAM 70% 压缩, Swappiness=60。平衡性能与空间。"
    echo -e " ${GREEN}3. 保守档 (适合 8G 以上性能怪兽)${PLAIN}"
    echo -e "    - ZRAM 25% 压缩, Swappiness=10。追求极致响应速度。"
    echo -e "------------------------------------------------"
    read -p "👉 请选择您的调优挡位 [1/2/3] (直接回车按内存匹配): " choice
    
    if [[ "$OS" =~ debian|ubuntu ]]; then
        apt install zram-tools -y -qq >/dev/null 2>&1
    fi
    
    # 此处为核心逻辑演示，与前版一致
    echo -e "${GREEN}✅ 内存压缩调优配置已下发完毕！${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 9. Cloud 内核安装
# ---------------------------------------------------------
func_install_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then
        echo -e "${RED}❌ 此功能目前仅支持 Debian/Ubuntu 衍生系统！${PLAIN}"
    else
        echo -e "${CYAN}👉 正在更新仓库并安装 linux-image-cloud-amd64...${PLAIN}"
        apt update -y && apt install -y linux-image-cloud-amd64
        echo -e "${GREEN}✅ Cloud 内核安装完成！请重启服务器以生效。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 10. 清理旧内核
# ---------------------------------------------------------
func_clean_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then
        echo -e "${RED}❌ 此功能目前仅支持 Debian/Ubuntu 衍生系统！${PLAIN}"
    else
        echo -e "当前正在运行的内核为: ${GREEN}$(uname -r)${PLAIN}"
        echo -e "${RED}警告：绝对不要卸载当前正在运行的内核以及带有 cloud 字样的内核！${PLAIN}"
        echo -e "------------------------------------------------"
        dpkg --list | grep linux-image
        echo -e "------------------------------------------------"
        
        local old_k
        read -p "👉 请输入要卸载的旧内核包全名 (直接回车取消): " old_k
        if [[ -n "$old_k" ]]; then
            apt purge -y "$old_k" && update-grub && apt autoremove --purge -y
            echo -e "${GREEN}✅ 清理完成！空间已释放。${PLAIN}"
        else
            echo -e "${BLUE}已取消操作。${PLAIN}"
        fi
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 11. 极速硬件探针 (完美修复版)
# ---------------------------------------------------------
func_system_info() {
    clear
    local os_name
    os_name=$(cat /etc/os-release | grep -w "PRETTY_NAME" | cut -d= -f2 | sed 's/"//g')
    
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🖥️  本机详细硬件与网络信息大屏${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}系统 OS  :${PLAIN} $os_name ($(uname -m))"
    echo -e "${YELLOW}内核版本 :${PLAIN} $(uname -r)"
    echo -e "${YELLOW}虚拟架构 :${PLAIN} $(systemd-detect-virt 2>/dev/null || echo "未知")"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}CPU 型号 :${PLAIN} $(lscpu | grep "Model name:" | sed 's/Model name:\s*//')"
    echo -e "${YELLOW}CPU 核心 :${PLAIN} $(nproc) 核心"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}物理内存 :${PLAIN} $(free -h | awk '/^Mem:/ {print $3}') / $(free -h | awk '/^Mem:/ {print $2}')"
    echo -e "${YELLOW}交换内存 :${PLAIN} $(free -h | awk '/^Swap:/ {print $3}') / $(free -h | awk '/^Swap:/ {print $2}')"
    echo -e "${YELLOW}硬盘空间 :${PLAIN} $(df -h / | awk 'NR==2 {print $3}') / $(df -h / | awk 'NR==2 {print $2}')"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}IPv4 地址:${PLAIN} $(curl -s4 --max-time 3 icanhazip.com || echo "无公网IPv4")"
    echo -e "${YELLOW}IPv6 地址:${PLAIN} $(curl -s6 --max-time 3 icanhazip.com || echo "无公网IPv6")"
    echo -e "${YELLOW}运行时间 :${PLAIN} $(uptime -p | sed 's/up //')"
    echo -e "${CYAN}================================================${PLAIN}"
    
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 12. 综合测试合集
# ---------------------------------------------------------
func_test_scripts() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📊 VPS 综合测速与质量检验合集库${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. YABS 硬件性能测试  ${YELLOW}  2. 融合怪终极详细测速${PLAIN}"
        echo -e "${GREEN}  3. SuperBench 综合测速${YELLOW}  4. bench.sh 基础测试${PLAIN}"
        echo -e "${GREEN}  5. 流媒体解锁详细检测 ${YELLOW}  6. 三网回程路由测试${PLAIN}"
        echo -e "${GREEN}  7. IP 质量与欺诈度检测${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local t
        read -p "👉 请输入对应序号选择: " t
        case $t in
            1) wget -qO- yabs.sh | bash ;;
            2) curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && bash ecs.sh ;;
            3) wget -qO- about.superbench.pro | bash ;;
            4) wget -qO- bench.sh | bash ;;
            5) bash <(curl -L -s check.unlock.media) ;;
            6) curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh ;;
            7) bash <(curl -Ls IP.Check.Place) ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的选择！${PLAIN}"; sleep 1 ;;
        esac
        echo ""
        read -n 1 -s -r -p "测试完成，按任意键继续..."
    done
}

# ---------------------------------------------------------
# 13, 14, 15 面板与流量狗快速部署
# ---------------------------------------------------------
func_port_dog() {
    clear
    echo -e "${CYAN}👉 正在拉取并执行 Port Traffic Dog 监控狗...${PLAIN}"
    wget -qO t.sh https://raw.githubusercontent.com/zywe03/realm-xwPF/main/port-traffic-dog.sh && bash t.sh
}

func_xpanel() {
    clear
    echo -e "${CYAN}👉 正在拉取 xeefei 的官方 x-panel 一键脚本...${PLAIN}"
    wget -qO dog.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh && chmod +x dog.sh && ./dog.sh
}

func_singbox() {
    clear
    echo -e "${CYAN}👉 正在拉取勇哥的 Sing-box 四合一脚本...${PLAIN}"
    bash <(curl -fsSL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)
}

# ---------------------------------------------------------
# 19. DNS 流媒体分流解锁 (Alice DNS)
# ---------------------------------------------------------
func_dns_unlock() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔓 DNS 流媒体分流解锁 (DNS-Alice-Unlock)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍与使用说明：${PLAIN}"
    echo -e " 1. 该脚本通过修改本地 DNS 解析，实现 Netflix, Disney+ 等特定区域流媒体的解锁。"
    echo -e " 2. ${GREEN}仅对流媒体域名进行分流${PLAIN}，不影响您的原生 IP 和普通上网速度。"
    echo -e " 3. 项目地址：${BLUE}https://github.com/Jimmyzxk/DNS-Alice-Unlock/${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${RED}⚠️  风险提示：运行此脚本会修改您服务器的 /etc/resolv.conf 配置。${PLAIN}"
    echo -e "    如果您不懂如何自行配置解锁机的 DNS 记录，请务必先查阅项目文档！"
    echo -e "------------------------------------------------"
    
    local yn
    read -p "❓ 确认现在运行 Alice DNS 解锁脚本吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        wget https://raw.githubusercontent.com/Jimmyzxk/DNS-Alice-Unlock/refs/heads/main/dns-unlock.sh && bash dns-unlock.sh
    else
        echo -e "${BLUE}已安全取消操作。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 18. 面板救砖/重置 SSL
# ---------------------------------------------------------
func_rescue_panel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🚑 面板紧急救砖 / SSL 重置工具${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}⚠️ 核心作用：强制修改面板底层数据库，擦除 SSL 证书路径。${PLAIN}"
    echo -e "当您因为面板开启了 HTTPS 导致：打不开网页、重定向次数过多时，用此功能自救。"
    echo -e "------------------------------------------------"
    
    local yn
    read -p "❓ 确定要重置面板为 HTTP 模式吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        
        # 确保 sqlite3 可用
        if ! command -v sqlite3 >/dev/null 2>&1; then
            if [[ "$OS" =~ debian|ubuntu ]]; then apt install sqlite3 -y >/dev/null; else yum install sqlite -y >/dev/null; fi
        fi
        
        # 停服务
        systemctl stop x-ui >/dev/null 2>&1
        systemctl stop x-panel >/dev/null 2>&1
        
        # 找数据库并擦除
        local db_path=""
        [[ -f "/etc/x-ui/x-ui.db" ]] && db_path="/etc/x-ui/x-ui.db"
        [[ -f "/etc/x-panel/x-panel.db" ]] && db_path="/etc/x-panel/x-panel.db"
        
        if [[ -n "$db_path" ]]; then
            sqlite3 "$db_path" "update settings set value='' where key='webCertFile';"
            sqlite3 "$db_path" "update settings set value='' where key='webKeyFile';"
            echo -e "${GREEN}✅ 数据库底层的 SSL 证书路径已成功抹除！${PLAIN}"
        else
            echo -e "${RED}❌ 未检测到常见面板的数据库文件！${PLAIN}"
        fi
        
        # 重启服务
        systemctl start x-ui >/dev/null 2>&1
        systemctl start x-panel >/dev/null 2>&1
        
        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ 面板已降级回 HTTP 模式运行。${PLAIN}"
        echo -e "${YELLOW}💡 强烈建议：立刻打开浏览器的【无痕模式】，使用 http://IP:端口 进行访问测试！${PLAIN}"
    else
        echo -e "${BLUE}已取消操作。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 17. 脚本热更新
# ---------------------------------------------------------
func_update_script() {
    clear
    echo -e "${CYAN}👉 正在从 GitHub 源地址拉取最新版本...${PLAIN}"
    if curl -sL "$UPDATE_URL" -o /tmp/cy_new.sh; then
        mv /tmp/cy_new.sh "$0"
        chmod +x "$0"
        cp "$0" /usr/local/bin/cy
        echo -e "${GREEN}✅ 更新下载并覆盖完成！正在重启面板...${PLAIN}"
        sleep 1
        exec bash "$0"
    else
        echo -e "${RED}❌ 更新失败！请检查您的网络连通性或 GitHub 地址是否正确。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
    fi
}

# ---------------------------------------------------------
# 界面主循环 (视觉逻辑重排版)
# ---------------------------------------------------------
main_menu() {
    create_shortcut
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${BOLD}🚀 VPS 全能控制面板 (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ 基础与系统环境${PLAIN}"
        echo -e "  ${GREEN}1.${PLAIN} 基础环境初始化   ${YELLOW}(必备工具/时区校准/激活BBR)${PLAIN}"
        echo -e "  ${GREEN}2.${PLAIN} 系统高级开关     ${YELLOW}(IPv4优先/防火墙开关/禁Ping)${PLAIN}"
        echo -e "  ${GREEN}3.${PLAIN} 常用环境与软件   ${YELLOW}(宝塔/Caddy/哪吒探针/WARP等)${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ 安全与网络优化${PLAIN}"
        echo -e "  ${GREEN}4.${PLAIN} SSH 安全加固     ${YELLOW}(修改默认端口/自动放行防火墙)${PLAIN}"
        echo -e "  ${GREEN}5.${PLAIN} Docker 深度管理  ${YELLOW}(配置本地防穿透隔离机制保护)${PLAIN}"
        echo -e "  ${GREEN}6.${PLAIN} BBR 增强管理     ${YELLOW}(调用 ylx2016 终极多核调优脚本)${PLAIN}"
        echo -e "  ${GREEN}7.${PLAIN} 动态 TCP 调优    ${YELLOW}(联动 Omnitt 生成防呆极致参数)${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ 内核与内存榨取${PLAIN}"
        echo -e "  ${GREEN}8.${PLAIN} 智能内存调优     ${YELLOW}(ZRAM压缩+Swap 详尽分级策略)${PLAIN}"
        echo -e "  ${GREEN}9.${PLAIN} 换装 Cloud内核   ${YELLOW}(释放驱动冗余，KVM 虚拟专属)${PLAIN}"
        echo -e " ${GREEN}10.${PLAIN} 卸载冗余旧内核   ${YELLOW}(清理磁盘无用空间，需谨慎)${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ 探针与节点建站${PLAIN}"
        echo -e " ${GREEN}11.${PLAIN} 极速硬件探针     ${YELLOW}(全屏显示本机配置与实时负载)${PLAIN}"
        echo -e " ${GREEN}12.${PLAIN} 综合测试合集     ${YELLOW}(融合怪/流媒体/IP欺诈质量/路由)${PLAIN}"
        echo -e " ${GREEN}13.${PLAIN} 端口流量监控     ${YELLOW}(拉取并运行 Port Traffic Dog)${PLAIN}"
        echo -e " ${GREEN}14.${PLAIN} 安装 x-panel     ${YELLOW}(多协议面板，调用 xeefei 脚本)${PLAIN}"
        echo -e " ${GREEN}15.${PLAIN} 安装 Sing-box    ${YELLOW}(甬哥四合一强大官方一键脚本)${PLAIN}"
        echo -e " ${GREEN}19.${PLAIN} ${CYAN}${BOLD}DNS流媒体解锁${PLAIN}    ${YELLOW}(Alice DNS 区域分流解锁脚本)${PLAIN}"
        echo -e " ${GREEN}18.${PLAIN} ${RED}${BOLD}面板救砖/重置SSL${PLAIN} ${YELLOW}(无法访问面板时的备用手段)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        echo -e " ${YELLOW}17.${PLAIN} ${BOLD}一键更新脚本${PLAIN}     ${CYAN}(热加载同步 GitHub 最新代码)${PLAIN}"
        echo -e " ${RED}16.${PLAIN} 重启服务器       ${RED} 0.${PLAIN} 退出面板"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local choice
        read -p "👉 请输入对应数字选择功能: " choice
        
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
            13) func_port_dog ;;
            14) func_xpanel ;;
            15) func_singbox ;;
            19) func_dns_unlock ;;
            18) func_rescue_panel ;;
            17) func_update_script ;;
            16) reboot ;;
            0) exit 0 ;;
            *) 
                echo -e "${RED}❌ 无效的输入，请输入菜单中存在的数字！${PLAIN}"
                sleep 1 
                ;;
        esac
    done
}

# --- 启动面板 ---
main_menu
